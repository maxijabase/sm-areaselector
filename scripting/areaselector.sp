#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"
#define HEIGHT_ADJUST_INCREMENT 8.0
#define DOUBLE_CLICK_TIME 0.3

// Area selection data structure
enum struct AreaData {
    float point1[3];        // First corner point
    float point2[3];        // Second corner point
    float mins[3];          // Minimum bounds
    float maxs[3];          // Maximum bounds
    float center[3];        // Center point
    float dimensions[3];    // Width, length, height
}

// Plugin info
public Plugin myinfo = {
    name = "Area Selector Library",
    author = "YourName",
    description = "Provides area selection functionality for other plugins",
    version = PLUGIN_VERSION,
    url = ""
};

// Natives
Handle g_hOnAreaSelected = null;
Handle g_hOnAreaCancelled = null;

// Selection state for each client
bool g_bIsSelecting[MAXPLAYERS + 1];
int g_iSelectionStep[MAXPLAYERS + 1];
float g_fPoints[MAXPLAYERS + 1][2][3];
float g_fVerticalOffset[MAXPLAYERS + 1];
float g_fLastClickTime[MAXPLAYERS + 1];
int g_iPreviousButtons[MAXPLAYERS + 1];
Handle g_hPreviewTimer[MAXPLAYERS + 1];

// Visual assets
int g_iLaserMaterial = -1;
int g_iHaloMaterial = -1;

// Callback storage
Handle g_hCallbacks[MAXPLAYERS + 1];
Handle g_hPlugins[MAXPLAYERS + 1];

// Native function declarations
native bool AreaSelector_Start(int client);
native bool AreaSelector_Cancel(int client);
native bool AreaSelector_IsSelecting(int client);
native bool AreaSelector_StartWithCallback(int client, Function callback);

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    CreateNative("AreaSelector_Start", Native_Start);
    CreateNative("AreaSelector_Cancel", Native_Cancel);
    CreateNative("AreaSelector_IsSelecting", Native_IsSelecting);
    CreateNative("AreaSelector_StartWithCallback", Native_StartWithCallback);
    
    RegPluginLibrary("area_selector");
    return APLRes_Success;
}

public void OnPluginStart() {
    // Create global forwards
    g_hOnAreaSelected = CreateGlobalForward("AreaSelector_OnAreaSelected", 
        ET_Ignore, 
        Param_Cell,     // client
        Param_Array,    // AreaData struct
        Param_Array,    // point1
        Param_Array,    // point2
        Param_Array,    // mins
        Param_Array,    // maxs
        Param_Array,    // center
        Param_Array     // dimensions
    );
    
    g_hOnAreaCancelled = CreateGlobalForward("AreaSelector_OnAreaCancelled", 
        ET_Ignore, 
        Param_Cell      // client
    );
    
    // Hook all current players
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i)) {
            SDKHook(i, SDKHook_PreThink, OnClientPreThink);
        }
    }
}

public void OnMapStart() {
    g_iLaserMaterial = PrecacheModel("materials/sprites/laser.vmt");
    g_iHaloMaterial = PrecacheModel("materials/sprites/halo01.vmt");
    PrecacheSound("buttons/button14.wav", true);
}

public void OnClientPutInServer(int client) {
    SDKHook(client, SDKHook_PreThink, OnClientPreThink);
    ResetClientData(client);
}

public void OnClientDisconnect(int client) {
    if (g_bIsSelecting[client]) {
        CancelSelection(client);
    }
    ResetClientData(client);
}

void ResetClientData(int client) {
    g_bIsSelecting[client] = false;
    g_iSelectionStep[client] = 0;
    g_fVerticalOffset[client] = 0.0;
    g_fLastClickTime[client] = 0.0;
    g_iPreviousButtons[client] = 0;
    g_hCallbacks[client] = null;
    g_hPlugins[client] = null;
}

// Native implementations
public int Native_Start(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    
    if (!IsValidClient(client)) {
        return false;
    }
    
    if (g_bIsSelecting[client]) {
        return false;
    }
    
    StartSelection(client);
    return true;
}

public int Native_StartWithCallback(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    Function callback = GetNativeFunction(2);
    
    if (!IsValidClient(client)) {
        return false;
    }
    
    if (g_bIsSelecting[client]) {
        return false;
    }
    
    g_hCallbacks[client] = CreateForward(ET_Ignore, Param_Cell, Param_Array);
    g_hPlugins[client] = plugin;
    AddToForward(g_hCallbacks[client], plugin, callback);
    
    StartSelection(client);
    return true;
}

public int Native_Cancel(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    
    if (!IsValidClient(client)) {
        return false;
    }
    
    if (!g_bIsSelecting[client]) {
        return false;
    }
    
    CancelSelection(client);
    return true;
}

public int Native_IsSelecting(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    
    if (!IsValidClient(client)) {
        return false;
    }
    
    return g_bIsSelecting[client];
}

void StartSelection(int client) {
    CleanupPreview(client);
    
    g_bIsSelecting[client] = true;
    g_iSelectionStep[client] = 1;
    g_fVerticalOffset[client] = 0.0;
    g_fLastClickTime[client] = 0.0;
    
    PrintToChat(client, "\x04[Area Selector]\x01 Point at a location and \x05double-click left mouse\x01 to set first corner.");
    PrintToChat(client, "\x04[Area Selector]\x01 Use \x05left-click\x01 to raise height and \x05right-click\x01 to lower height.");
    PrintToChat(client, "\x04[Area Selector]\x01 Current height offset: \x030\x01 units");
    
    g_hPreviewTimer[client] = CreateTimer(0.1, Timer_Preview, client, TIMER_REPEAT);
}

void CancelSelection(int client) {
    CleanupPreview(client);
    g_bIsSelecting[client] = false;
    g_iSelectionStep[client] = 0;
    g_fVerticalOffset[client] = 0.0;
    
    // Fire cancelled forward
    Call_StartForward(g_hOnAreaCancelled);
    Call_PushCell(client);
    Call_Finish();
    
    // Clean up callback if exists
    if (g_hCallbacks[client] != null) {
        delete g_hCallbacks[client];
        g_hCallbacks[client] = null;
    }
    g_hPlugins[client] = null;
    
    PrintToChat(client, "\x04[Area Selector]\x01 Selection cancelled.");
}

void CleanupPreview(int client) {
    if (g_hPreviewTimer[client] != null) {
        delete g_hPreviewTimer[client];
        g_hPreviewTimer[client] = null;
    }
}

public Action Timer_Preview(Handle timer, int client) {
    if (!IsClientInGame(client) || !g_bIsSelecting[client]) {
        g_hPreviewTimer[client] = null;
        return Plugin_Stop;
    }
    
    float eyePos[3], eyeAng[3], endPos[3];
    GetClientEyePosition(client, eyePos);
    GetClientEyeAngles(client, eyeAng);
    
    TR_TraceRayFilter(eyePos, eyeAng, MASK_SOLID, RayType_Infinite, TraceFilterPlayers);
    
    if (TR_DidHit()) {
        TR_GetEndPosition(endPos);
        endPos[2] += g_fVerticalOffset[client];
        
        // Round to whole numbers
        for (int i = 0; i < 3; i++) {
            endPos[i] = float(RoundToFloor(endPos[i]));
        }
        
        // Show marker at current position
        int color[4] = {0, 255, 0, 255}; // Green for first point
        if (g_iSelectionStep[client] == 2) {
            color = {255, 165, 0, 255}; // Orange for second point
        }
        
        TE_SetupBeamRingPoint(endPos, 5.0, 8.0, g_iLaserMaterial, g_iHaloMaterial, 0, 15, 0.1, 2.0, 0.0, color, 1, 0);
        TE_SendToClient(client);
        
        // Preview the area if we have both points
        if (g_iSelectionStep[client] == 2) {
            float mins[3], maxs[3];
            
            for (int i = 0; i < 3; i++) {
                mins[i] = (g_fPoints[client][0][i] < endPos[i]) ? g_fPoints[client][0][i] : endPos[i];
                maxs[i] = (g_fPoints[client][0][i] > endPos[i]) ? g_fPoints[client][0][i] : endPos[i];
            }
            
            // Draw preview box
            int boxColor[4] = {0, 255, 255, 255}; // Cyan
            TE_SendBeamBoxToClient(client, mins, maxs, g_iLaserMaterial, g_iHaloMaterial, 0, 30, 0.1, 3.0, 3.0, 2, 1.0, boxColor, 0);
            
            // Display dimensions
            float width = maxs[0] - mins[0];
            float length = maxs[1] - mins[1];
            float height = maxs[2] - mins[2];
            
            PrintHintText(client, "Area: %.0f x %.0f x %.0f units", width, length, height);
        } else {
            PrintHintText(client, "Height offset: %.0f units", g_fVerticalOffset[client]);
        }
    }
    
    return Plugin_Continue;
}

public Action OnClientPreThink(int client) {
    if (!IsClientInGame(client) || !g_bIsSelecting[client])
        return Plugin_Continue;
    
    int currentButtons = GetClientButtons(client);
    
    // Left click handling
    if ((currentButtons & IN_ATTACK) && !(g_iPreviousButtons[client] & IN_ATTACK)) {
        float currentTime = GetGameTime();
        float timeSinceLastClick = currentTime - g_fLastClickTime[client];
        
        if (timeSinceLastClick <= DOUBLE_CLICK_TIME) {
            ProcessClick(client);
            g_fLastClickTime[client] = 0.0;
        } else {
            g_fVerticalOffset[client] += HEIGHT_ADJUST_INCREMENT;
            PrintHintText(client, "Height: %.0f units | Double-click to set point", g_fVerticalOffset[client]);
            EmitSoundToClient(client, "buttons/button14.wav");
            g_fLastClickTime[client] = currentTime;
        }
    }
    
    // Right click for decreasing height
    if ((currentButtons & IN_ATTACK2) && !(g_iPreviousButtons[client] & IN_ATTACK2)) {
        g_fVerticalOffset[client] -= HEIGHT_ADJUST_INCREMENT;
        PrintHintText(client, "Height: %.0f units | Double-click to set point", g_fVerticalOffset[client]);
        EmitSoundToClient(client, "buttons/button14.wav");
    }
    
    g_iPreviousButtons[client] = currentButtons;
    return Plugin_Continue;
}

void ProcessClick(int client) {
    float eyePos[3], eyeAng[3], endPos[3];
    GetClientEyePosition(client, eyePos);
    GetClientEyeAngles(client, eyeAng);
    
    TR_TraceRayFilter(eyePos, eyeAng, MASK_SOLID, RayType_Infinite, TraceFilterPlayers);
    
    if (TR_DidHit()) {
        TR_GetEndPosition(endPos);
        endPos[2] += g_fVerticalOffset[client];
        
        for (int i = 0; i < 3; i++) {
            endPos[i] = float(RoundToFloor(endPos[i]));
        }
        
        if (g_iSelectionStep[client] == 1) {
            // Set first point
            for (int i = 0; i < 3; i++) {
                g_fPoints[client][0][i] = endPos[i];
            }
            
            PrintToChat(client, "\x04[Area Selector]\x01 First corner set at: %.0f, %.0f, %.0f", 
                endPos[0], endPos[1], endPos[2]);
            PrintToChat(client, "\x04[Area Selector]\x01 Now set the second corner.");
            
            g_fVerticalOffset[client] = 0.0;
            g_iSelectionStep[client] = 2;
        }
        else if (g_iSelectionStep[client] == 2) {
            // Set second point and complete selection
            for (int i = 0; i < 3; i++) {
                g_fPoints[client][1][i] = endPos[i];
            }
            
            PrintToChat(client, "\x04[Area Selector]\x01 Second corner set at: %.0f, %.0f, %.0f", 
                endPos[0], endPos[1], endPos[2]);
            
            CompleteSelection(client);
        }
    }
}

void CompleteSelection(int client) {
    AreaData area;
    
    // Copy points
    for (int i = 0; i < 3; i++) {
        area.point1[i] = g_fPoints[client][0][i];
        area.point2[i] = g_fPoints[client][1][i];
    }
    
    // Calculate bounds
    for (int i = 0; i < 3; i++) {
        area.mins[i] = (area.point1[i] < area.point2[i]) ? area.point1[i] : area.point2[i];
        area.maxs[i] = (area.point1[i] > area.point2[i]) ? area.point1[i] : area.point2[i];
        area.center[i] = (area.mins[i] + area.maxs[i]) / 2.0;
        area.dimensions[i] = area.maxs[i] - area.mins[i];
    }
    
    // Fire the forward
    Call_StartForward(g_hOnAreaSelected);
    Call_PushCell(client);
    Call_PushArray(area, sizeof(area));
    Call_PushArray(area.point1, 3);
    Call_PushArray(area.point2, 3);
    Call_PushArray(area.mins, 3);
    Call_PushArray(area.maxs, 3);
    Call_PushArray(area.center, 3);
    Call_PushArray(area.dimensions, 3);
    Call_Finish();
    
    // Fire callback if exists
    if (g_hCallbacks[client] != null) {
        Call_StartForward(g_hCallbacks[client]);
        Call_PushCell(client);
        Call_PushArray(area, sizeof(area));
        Call_Finish();
        
        delete g_hCallbacks[client];
        g_hCallbacks[client] = null;
    }
    
    // Cleanup
    CleanupPreview(client);
    g_bIsSelecting[client] = false;
    g_iSelectionStep[client] = 0;
    g_fVerticalOffset[client] = 0.0;
    g_hPlugins[client] = null;
    
    PrintToChat(client, "\x04[Area Selector]\x01 Area selection complete!");
}

public bool TraceFilterPlayers(int entity, int contentsMask) {
    return entity > MaxClients;
}

bool IsValidClient(int client) {
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

// Beam box rendering
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