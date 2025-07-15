#if defined _area_selector_included
  #endinput
#endif
#define _area_selector_included

/**
 * Area Selection Library
 * Provides area selection functionality for SourceMod plugins
 */

/**
 * Area data structure containing all information about a selected area
 */
enum struct AreaData {
    float point1[3];        // First corner point
    float point2[3];        // Second corner point
    float mins[3];          // Minimum bounds
    float maxs[3];          // Maximum bounds
    float center[3];        // Center point
    float dimensions[3];    // Width (X), Length (Y), Height (Z)
}

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

/**
 * Callback function type for area selection completion
 *
 * @param client        Client who completed the selection
 * @param area          AreaData structure with all area information
 * @noreturn
 */
typeset AreaSelectedCallback {
    function void(int client, AreaData area);
};

/**
 * Start area selection for a client
 *
 * @param client        Client index to start selection for
 * @return              True if selection started, false if client is already selecting
 */
native bool AreaSelector_Start(int client);

/**
 * Start area selection for a client with a specific callback
 *
 * @param client        Client index to start selection for
 * @param callback      Function to call when selection is complete
 * @return              True if selection started, false if client is already selecting
 */
native bool AreaSelector_StartWithCallback(int client, AreaSelectedCallback callback);

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

/**
 * Helper function to calculate volume of an area
 *
 * @param dimensions    Dimensions array from AreaData
 * @return              Volume of the area
 */
stock float AreaSelector_GetVolume(float dimensions[3]) {
    return dimensions[0] * dimensions[1] * dimensions[2];
}

/**
 * Helper function to calculate surface area of an area (all 6 faces)
 *
 * @param dimensions    Dimensions array from AreaData
 * @return              Total surface area
 */
stock float AreaSelector_GetSurfaceArea(float dimensions[3]) {
    return 2.0 * (dimensions[0] * dimensions[1] + dimensions[0] * dimensions[2] + dimensions[1] * dimensions[2]);
}

/**
 * Helper function to check if a point is inside an area
 *
 * @param point         Point to check
 * @param mins          Minimum bounds of the area
 * @param maxs          Maximum bounds of the area
 * @return              True if point is inside area, false otherwise
 */
stock bool AreaSelector_IsPointInArea(float point[3], float mins[3], float maxs[3]) {
    return (point[0] >= mins[0] && point[0] <= maxs[0] &&
            point[1] >= mins[1] && point[1] <= maxs[1] &&
            point[2] >= mins[2] && point[2] <= maxs[2]);
}

public SharedPlugin __pl_area_selector = {
    name = "area_selector",
    file = "area_selector.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};