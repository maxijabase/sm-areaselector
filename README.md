# [LIB/API] Area Selector

A SourceMod library that provides 3D area selection functionality for Source engine games. This plugin allows players to select rectangular areas in the game world using an intuitive point-and-click interface with visual feedback.

## Features

- **Interactive area selection** - Players can select areas by pointing and double-clicking
- **Height adjustment** - Real-time height offset control with mouse clicks
- **Built-in visual feedback** - Beam rings and area preview boxes show selection progress
- **Audio feedback** - Button click sounds for height adjustments
- **Comprehensive area data** - Complete information about selected areas

## Installation

1. Place `areaselector.smx` in your `plugins/` folder
2. Restart your server or load the plugin with `sm plugins load areaselector`

## How It Works

### Selection Process

1. **Start selection** - Plugin calls `AreaSelector_Start(client)`
2. **First corner** - Player aims and double-clicks to set first corner
3. **Height adjustment** - Player can use left/right click to adjust height
4. **Second corner** - Player aims and double-clicks to set second corner
5. **Completion** - Area data is provided via forwards or callbacks

### Controls During Selection

- **Double-click left mouse** - Set corner point
- **Single left-click** - Raise height by 8 units
- **Right-click** - Lower height by 8 units

### Visual Indicators

- **Green ring** - Shows first corner position
- **Orange ring** - Shows second corner position  
- **Cyan wireframe box** - Live preview of selected area (during second corner selection)
- **Button click sounds** - Audio feedback when adjusting height

## Usage for Plugin Developers

### Basic Usage

```sourcepawn
#include <areaselector>

public void OnPluginStart() {
    RegAdminCmd("sm_selectarea", Command_SelectArea, ADMFLAG_GENERIC);
}

public Action Command_SelectArea(int client, int args) {
    if (AreaSelector_Start(client)) {
        PrintToChat(client, "Start selecting your area!");
    }
    return Plugin_Handled;
}

public void AreaSelector_OnAreaSelected(int client, AreaData area, float point1[3], 
                                      float point2[3], float mins[3], float maxs[3], 
                                      float center[3], float dimensions[3]) {
    PrintToChat(client, "Area selected! Size: %.0fx%.0fx%.0f", 
               dimensions[0], dimensions[1], dimensions[2]);
}
```

### Natives

```sourcepawn
/**
 * Start area selection for a client
 *
 * @param client        Client index to start selection for
 * @return              True if selection started, false if client is already selecting
 */
native bool AreaSelector_Start(int client);

/**
 * Cancel area selection for a client
 *
 * @param client        Client index to cancel selection for
 * @return              True if selection was cancelled, false if client wasn't selecting
 */
native bool AreaSelector_Cancel(int client);

/**
 * Check if a client is currently selecting an area
 *
 * @param client        Client index to check
 * @return              True if client is selecting, false otherwise
 */
native bool AreaSelector_IsSelecting(int client);
```

### Forwards

```sourcepawn
/**
 * Called when a client completes an area selection
 *
 * @param client        Client index who completed the selection
 * @param area          AreaData structure with all area information
 * @param point1        First corner point coordinates
 * @param point2        Second corner point coordinates
 * @param mins          Minimum bounds of the area
 * @param maxs          Maximum bounds of the area
 * @param center        Center point of the area
 * @param dimensions    Dimensions of the area (width, length, height)
 * @noreturn
 */
forward void AreaSelector_OnAreaSelected(int client, AreaData area, float point1[3], float point2[3], float mins[3], float maxs[3], float center[3], float dimensions[3]);

/**
 * Called when a client cancels an area selection
 *
 * @param client        Client index who cancelled the selection
 * @noreturn
 */
forward void AreaSelector_OnAreaCancelled(int client);

/**
 * Called during area selection to allow plugins to handle display updates
 * This forward is called every 0.1 seconds while a client is selecting an area
 *
 * @param client        Client index who is selecting
 * @param step          Selection step (1 = first corner, 2 = second corner)
 * @param currentPos    Current position the client is aiming at [3]
 * @param heightOffset  Current height offset being applied
 * @param firstPoint    First corner coordinates [3] (valid when step == 2)
 * @param dimensions    Area dimensions [3] (width, length, height - valid when step == 2)
 * @param volume        Area volume (valid when step == 2)
 * @noreturn
 */
forward void AreaSelector_OnDisplayUpdate(int client, int step, float currentPos[3], float heightOffset, float firstPoint[3], float dimensions[3], float volume);
```

### Area Data Structure

```sourcepawn
enum struct AreaData {
    float point1[3];        // First corner coordinates
    float point2[3];        // Second corner coordinates  
    float mins[3];          // Minimum bounds (smallest X,Y,Z)
    float maxs[3];          // Maximum bounds (largest X,Y,Z)
    float center[3];        // Center point of the area
    float dimensions[3];    // Width, Length, Height
}
```

### Helper Functions

```sourcepawn
// Calculate volume
float volume = AreaSelector_GetVolume(area.dimensions);

// Calculate surface area
float surface = AreaSelector_GetSurfaceArea(area.dimensions);

// Check if point is inside area
bool inside = AreaSelector_IsPointInArea(playerPos, area.mins, area.maxs);
```

## Display Integration Examples

The library provides all visual feedback (rings, boxes, sounds). These examples show how to add text-based information:

### HUD Display
```sourcepawn
Handle g_hHudSync;

public void OnPluginStart() {
    g_hHudSync = CreateHudSynchronizer();
}

public void AreaSelector_OnDisplayUpdate(int client, int step, float currentPos[3], 
                                       float heightOffset, float firstPoint[3], 
                                       float dimensions[3], float volume) {
    char text[256];
    if (step == 1) {
        Format(text, sizeof(text), "Setting Corner 1\nPos: %.0f, %.0f, %.0f\nHeight: %.0f", 
               currentPos[0], currentPos[1], currentPos[2], heightOffset);
    } else {
        Format(text, sizeof(text), "Setting Corner 2\nArea: %.0fx%.0fx%.0f\nVolume: %.0f", 
               dimensions[0], dimensions[1], dimensions[2], volume);
    }
    
    SetHudTextParams(-1.0, 0.3, 0.15, 255, 255, 255, 255);
    ShowSyncHudText(client, g_hHudSync, text);
}
```

### Chat Display
```sourcepawn
public void AreaSelector_OnDisplayUpdate(int client, int step, float currentPos[3], 
                                       float heightOffset, float firstPoint[3], 
                                       float dimensions[3], float volume) {
    if (step == 1) {
        PrintToChat(client, "Step 1/2 - Position: %.0f, %.0f, %.0f | Height: %.0f", 
                   currentPos[0], currentPos[1], currentPos[2], heightOffset);
    } else {
        PrintToChat(client, "Step 2/2 - Preview: %.0fx%.0fx%.0f (%.0f volume)", 
                   dimensions[0], dimensions[1], dimensions[2], volume);
    }
}
```

## Advanced Usage

### Multiple Area Storage
```sourcepawn
#define MAX_AREAS 100
AreaData g_Areas[MAX_AREAS];
int g_AreaCount = 0;

public void AreaSelector_OnAreaSelected(int client, AreaData area, float point1[3], 
                                      float point2[3], float mins[3], float maxs[3], 
                                      float center[3], float dimensions[3]) {
    if (g_AreaCount < MAX_AREAS) {
        g_Areas[g_AreaCount] = area;
        g_AreaCount++;
        PrintToChat(client, "Area saved! Total areas: %d", g_AreaCount);
    }
}
```

## Technical Details

- **Update frequency**: Display updates every 0.1 seconds during selection
- **Coordinate precision**: Positions are rounded to whole numbers
- **Height increment**: 8 units per click (configurable in source)
- **Double-click time**: 0.3 seconds maximum between clicks
- **Visual range**: Optimized for reasonable viewing distances