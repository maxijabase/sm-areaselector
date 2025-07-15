#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <areaselector>

#define MAX_AREAS 64
#define AREA_DISPLAY_INTERVAL 1.0 // How often to refresh the area display

public Plugin myinfo = {
    name = "Area Selector Example - Persistent Areas",
    author = "YourName",
    description = "Example plugin showing persistent area display using Area Selector library",
    version = "1.0.0",
    url = ""
};

// Stored area data
int g_iAreaCount = 0;
AreaData g_Areas[MAX_AREAS];
int g_iAreaColors[MAX_AREAS][4];
char g_sAreaNames[MAX_AREAS][64];
int g_iAreaCreators[MAX_AREAS];

// Display timer
Handle g_hDisplayTimer = null;

// Beam sprites
int g_iLaserMaterial = -1;
int g_iHaloMaterial = -1;

// HUD synchronizer for selection display
Handle g_hSelectionHudSync = null;

// Display preferences
bool g_bShowSelectionHUD[MAXPLAYERS + 1] = {true, ...};

public void OnPluginStart() {
    RegAdminCmd("sm_createarea", Command_CreateArea, ADMFLAG_GENERIC, "Create a new persistent area");
    RegAdminCmd("sm_deletearea", Command_DeleteArea, ADMFLAG_GENERIC, "Delete an area by ID");
    RegAdminCmd("sm_listareas", Command_ListAreas, ADMFLAG_GENERIC, "List all created areas");
    RegAdminCmd("sm_clearallareas", Command_ClearAllAreas, ADMFLAG_GENERIC, "Clear all areas");
    RegAdminCmd("sm_showareas", Command_ShowAreas, ADMFLAG_GENERIC, "Toggle area display");
    RegAdminCmd("sm_areainfo", Command_AreaInfo, ADMFLAG_GENERIC, "Get info about the area you're standing in");
    RegAdminCmd("sm_toggleselectionhud", Command_ToggleSelectionHUD, ADMFLAG_GENERIC, "Toggle selection HUD display");
    
    // Create HUD synchronizer for selection display
    g_hSelectionHudSync = CreateHudSynchronizer();
}

public void OnMapStart() {
    g_iLaserMaterial = PrecacheModel("materials/sprites/laser.vmt");
    g_iHaloMaterial = PrecacheModel("materials/sprites/halo01.vmt");
    
    // Start the display timer
    if (g_hDisplayTimer == null) {
        g_hDisplayTimer = CreateTimer(AREA_DISPLAY_INTERVAL, Timer_DisplayAreas, _, TIMER_REPEAT);
    }
}

public void OnMapEnd() {
    // Clear areas on map change
    g_iAreaCount = 0;
    
    if (g_hDisplayTimer != null) {
        delete g_hDisplayTimer;
        g_hDisplayTimer = null;
    }
}

public void OnClientDisconnect(int client) {
    // Clear any selection HUD when client disconnects
    g_bShowSelectionHUD[client] = true; // Reset to default
}

public Action Command_CreateArea(int client, int args) {
    if (g_iAreaCount >= MAX_AREAS) {
        PrintToChat(client, "[Areas] Maximum number of areas (%d) reached!", MAX_AREAS);
        return Plugin_Handled;
    }
    
    if (!AreaSelector_IsSelecting(client)) {
        if (AreaSelector_Start(client)) {
            PrintToChat(client, "[Areas] Start selecting your area. Area will be saved when complete.");
            PrintToChat(client, "[Areas] Use 'sm_toggleselectionhud' to toggle HUD display during selection.");
        } else {
            PrintToChat(client, "[Areas] Failed to start area selection.");
        }
    } else {
        PrintToChat(client, "[Areas] You are already selecting an area!");
    }
    
    return Plugin_Handled;
}

public Action Command_DeleteArea(int client, int args) {
    if (args < 1) {
        PrintToChat(client, "[Areas] Usage: sm_deletearea <area_id>");
        return Plugin_Handled;
    }
    
    char arg[8];
    GetCmdArg(1, arg, sizeof(arg));
    int areaId = StringToInt(arg);
    
    if (areaId < 0 || areaId >= g_iAreaCount) {
        PrintToChat(client, "[Areas] Invalid area ID. Use sm_listareas to see valid IDs.");
        return Plugin_Handled;
    }
    
    // Remove area by shifting all subsequent areas
    for (int i = areaId; i < g_iAreaCount - 1; i++) {
        g_Areas[i] = g_Areas[i + 1];
        g_iAreaColors[i] = g_iAreaColors[i + 1];
        g_sAreaNames[i] = g_sAreaNames[i + 1];
        g_iAreaCreators[i] = g_iAreaCreators[i + 1];
    }
    
    g_iAreaCount--;
    PrintToChat(client, "[Areas] Area #%d deleted. Total areas: %d", areaId, g_iAreaCount);
    
    return Plugin_Handled;
}

public Action Command_ListAreas(int client, int args) {
    if (g_iAreaCount == 0) {
        PrintToChat(client, "[Areas] No areas have been created yet.");
        return Plugin_Handled;
    }
    
    PrintToChat(client, "[Areas] Listing all %d areas:", g_iAreaCount);
    
    for (int i = 0; i < g_iAreaCount; i++) {
        char creatorName[64] = "Unknown";
        if (g_iAreaCreators[i] > 0 && IsClientInGame(g_iAreaCreators[i])) {
            GetClientName(g_iAreaCreators[i], creatorName, sizeof(creatorName));
        }
        
        PrintToChat(client, "  #%d: %s (%.0fx%.0fx%.0f) by %s", 
            i, 
            g_sAreaNames[i],
            g_Areas[i].dimensions[0],
            g_Areas[i].dimensions[1],
            g_Areas[i].dimensions[2],
            creatorName
        );
    }
    
    return Plugin_Handled;
}

public Action Command_ClearAllAreas(int client, int args) {
    g_iAreaCount = 0;
    PrintToChat(client, "[Areas] All areas have been cleared.");
    return Plugin_Handled;
}

public Action Command_ShowAreas(int client, int args) {
    if (g_hDisplayTimer != null) {
        delete g_hDisplayTimer;
        g_hDisplayTimer = null;
        PrintToChat(client, "[Areas] Area display disabled.");
    } else {
        g_hDisplayTimer = CreateTimer(AREA_DISPLAY_INTERVAL, Timer_DisplayAreas, _, TIMER_REPEAT);
        PrintToChat(client, "[Areas] Area display enabled.");
    }
    
    return Plugin_Handled;
}

public Action Command_ToggleSelectionHUD(int client, int args) {
    g_bShowSelectionHUD[client] = !g_bShowSelectionHUD[client];
    
    if (g_bShowSelectionHUD[client]) {
        PrintToChat(client, "[Areas] Selection HUD enabled.");
    } else {
        PrintToChat(client, "[Areas] Selection HUD disabled.");
        // Clear current HUD if they're selecting
        if (AreaSelector_IsSelecting(client)) {
            ClearSyncHud(client, g_hSelectionHudSync);
        }
    }
    
    return Plugin_Handled;
}

public Action Command_AreaInfo(int client, int args) {
    float playerPos[3];
    GetClientAbsOrigin(client, playerPos);
    
    bool foundArea = false;
    for (int i = 0; i < g_iAreaCount; i++) {
        if (AreaSelector_IsPointInArea(playerPos, g_Areas[i].mins, g_Areas[i].maxs)) {
            char creatorName[64] = "Unknown";
            if (g_iAreaCreators[i] > 0 && IsClientInGame(g_iAreaCreators[i])) {
                GetClientName(g_iAreaCreators[i], creatorName, sizeof(creatorName));
            }
            
            PrintToChat(client, "[Areas] You are in area #%d: %s", i, g_sAreaNames[i]);
            PrintToChat(client, "  Size: %.0f x %.0f x %.0f", 
                g_Areas[i].dimensions[0],
                g_Areas[i].dimensions[1],
                g_Areas[i].dimensions[2]
            );
            PrintToChat(client, "  Created by: %s", creatorName);
            PrintToChat(client, "  Center: %.1f, %.1f, %.1f",
                g_Areas[i].center[0],
                g_Areas[i].center[1],
                g_Areas[i].center[2]
            );
            
            foundArea = true;
        }
    }
    
    if (!foundArea) {
        PrintToChat(client, "[Areas] You are not inside any area.");
    }
    
    return Plugin_Handled;
}

// Forward handler - saves the area when selection is complete
public void AreaSelector_OnAreaSelected(int client, AreaData area, float point1[3], float point2[3], float mins[3], float maxs[3], float center[3], float dimensions[3]) {
    if (g_iAreaCount >= MAX_AREAS) {
        PrintToChat(client, "[Areas] Cannot save area - maximum limit reached!");
        return;
    }
    
    // Clear selection HUD
    ClearSyncHud(client, g_hSelectionHudSync);
    
    // Save the area
    g_Areas[g_iAreaCount] = area;
    g_iAreaCreators[g_iAreaCount] = client;
    
    // Generate a name for the area
    Format(g_sAreaNames[g_iAreaCount], 64, "Area_%d", g_iAreaCount + 1);
    
    // Assign a random color to the area
    g_iAreaColors[g_iAreaCount][0] = GetRandomInt(50, 255);  // R
    g_iAreaColors[g_iAreaCount][1] = GetRandomInt(50, 255);  // G
    g_iAreaColors[g_iAreaCount][2] = GetRandomInt(50, 255);  // B
    g_iAreaColors[g_iAreaCount][3] = 255;                    // A
    
    PrintToChat(client, "[Areas] Area #%d created successfully!", g_iAreaCount);
    PrintToChat(client, "  Name: %s", g_sAreaNames[g_iAreaCount]);
    PrintToChat(client, "  Size: %.0f x %.0f x %.0f", dimensions[0], dimensions[1], dimensions[2]);
    PrintToChat(client, "  Volume: %.0f cubic units", AreaSelector_GetVolume(dimensions));
    
    g_iAreaCount++;
}

// Forward handler - clear HUD when selection is cancelled
public void AreaSelector_OnAreaCancelled(int client) {
    ClearSyncHud(client, g_hSelectionHudSync);
    PrintToChat(client, "[Areas] Area selection cancelled.");
}

// Forward handler - display selection progress
public void AreaSelector_OnDisplayUpdate(int client, int step, float currentPos[3], float heightOffset, float firstPoint[3], float dimensions[3], float volume) {
    // Only show HUD if client has it enabled
    if (!g_bShowSelectionHUD[client]) {
        return;
    }
    
    char hudText[512];
    
    if (step == 1) {
        // First corner selection
        Format(hudText, sizeof(hudText), 
            "═══ AREA SELECTION ═══\n" ...
            "Step 1/2: Setting First Corner\n" ...
            "\n" ...
            "Position: %.0f, %.0f, %.0f\n" ...
            "Height Offset: %.0f units\n" ...
            "\n" ...
            "Controls:\n" ...
            "• Double-click: Set corner\n" ...
            "• Left-click: Raise height (+8)\n" ...
            "• Right-click: Lower height (-8)\n" ...
            "\n" ...
            "Use 'sm_toggleselectionhud' to hide this",
            currentPos[0], currentPos[1], currentPos[2],
            heightOffset);
    } else if (step == 2) {
        // Second corner selection with area preview
        Format(hudText, sizeof(hudText), 
            "═══ AREA SELECTION ═══\n" ...
            "Step 2/2: Setting Second Corner\n" ...
            "\n" ...
            "Position: %.0f, %.0f, %.0f\n" ...
            "Height Offset: %.0f units\n" ...
            "\n" ...
            "Area Preview:\n" ...
            "• Width: %.0f units\n" ...
            "• Length: %.0f units\n" ...
            "• Height: %.0f units\n" ...
            "• Volume: %.0f units³\n" ...
            "\n" ...
            "Double-click to complete selection",
            currentPos[0], currentPos[1], currentPos[2],
            heightOffset,
            dimensions[0], dimensions[1], dimensions[2],
            volume);
    }
    
    // Display HUD text using synchronizer
    SetHudTextParams(-1.0, 0.15, 0.15, 100, 200, 255, 255, 0, 0.0, 0.0, 0.0);
    ShowSyncHudText(client, g_hSelectionHudSync, hudText);
}

// Timer to display all areas
public Action Timer_DisplayAreas(Handle timer) {
    if (g_iAreaCount == 0) {
        return Plugin_Continue;
    }
    
    // Draw each area for all clients
    for (int i = 0; i < g_iAreaCount; i++) {
        DrawAreaForAll(i);
    }
    
    return Plugin_Continue;
}

void DrawAreaForAll(int areaIndex) {
    // Draw the area box for all clients
    for (int client = 1; client <= MaxClients; client++) {
        if (!IsClientInGame(client)) {
            continue;
        }
        
        // Check if client is close enough to see the area (optimization)
        float clientPos[3];
        GetClientAbsOrigin(client, clientPos);
        
        float distance = GetVectorDistance(clientPos, g_Areas[areaIndex].center);
        if (distance > 3000.0) { // Don't draw areas too far away
            continue;
        }
        
        // Draw the box
        TE_SendBeamBoxToClient(
            client,
            g_Areas[areaIndex].maxs, // Note: this should be maxs first for correct box drawing
            g_Areas[areaIndex].mins,
            g_iLaserMaterial,
            g_iHaloMaterial,
            0,
            30,
            AREA_DISPLAY_INTERVAL + 0.1, // Lifetime slightly longer than refresh rate
            2.0,
            2.0,
            2,
            0.0,
            g_iAreaColors[areaIndex],
            0
        );
    }
}

// Beam box rendering function
stock void TE_SendBeamBoxToClient(int client, float uppercorner[3], float bottomcorner[3], int ModelIndex, int HaloIndex, int StartFrame, int FrameRate, float Life, float Width, float EndWidth, int FadeLength, float Amplitude, int Color[4], int Speed) {
    float tc1[3], tc2[3], tc3[3], tc4[3], tc5[3], tc6[3];
    
    tc1[0] = bottomcorner[0];
    tc1[1] = uppercorner[1];
    tc1[2] = uppercorner[2];
    
    tc2[0] = uppercorner[0];
    tc2[1] = bottomcorner[1];
    tc2[2] = uppercorner[2];
    
    tc3[0] = uppercorner[0];
    tc3[1] = uppercorner[1];
    tc3[2] = bottomcorner[2];
    
    tc4[0] = uppercorner[0];
    tc4[1] = bottomcorner[1];
    tc4[2] = bottomcorner[2];
    
    tc5[0] = bottomcorner[0];
    tc5[1] = uppercorner[1];
    tc5[2] = bottomcorner[2];
    
    tc6[0] = bottomcorner[0];
    tc6[1] = bottomcorner[1];
    tc6[2] = uppercorner[2];
    
    // Draw all edges
    TE_SetupBeamPoints(uppercorner, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToClient(client);
    TE_SetupBeamPoints(uppercorner, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToClient(client);
    TE_SetupBeamPoints(uppercorner, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToClient(client);
    TE_SetupBeamPoints(tc6, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToClient(client);
    TE_SetupBeamPoints(tc6, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToClient(client);
    TE_SetupBeamPoints(tc6, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToClient(client);
    TE_SetupBeamPoints(tc4, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToClient(client);
    TE_SetupBeamPoints(tc5, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToClient(client);
    TE_SetupBeamPoints(tc5, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToClient(client);
    TE_SetupBeamPoints(tc5, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToClient(client);
    TE_SetupBeamPoints(tc4, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToClient(client);
    TE_SetupBeamPoints(tc4, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
    TE_SendToClient(client);
}