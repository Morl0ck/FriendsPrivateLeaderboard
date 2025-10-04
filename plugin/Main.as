// Entry point. Keeps the script running; UI is rendered via Render() callbacks.
void Main() {
    LoadSettings();
    while (true) {
        yield();
    }
}

// Render UI each frame
void Render() {
    RenderFPLWindow();
}

// Menu toggle
void RenderMenu() {
    if (UI::MenuItem("Friend Private Leaderboards", "", g_ShowWindow)) {
        g_ShowWindow = !g_ShowWindow;
    }
}

// Helper to get current map UID as map_id for API
string GetCurrentMapId() {
    auto app = GetApp();
    if (app is null) return "";
    if (app.RootMap is null) return "";
    auto map = app.RootMap;
    if (map !is null && map.MapInfo !is null && map.MapInfo.MapUid.Length > 0) return map.MapInfo.MapUid;
    if (map !is null && map.EdChallengeId.Length > 0) return map.EdChallengeId;
    return "";
}
