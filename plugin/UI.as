// Simple UI for the Friend Private Leaderboards

bool g_ShowWindow = true;
array<LeaderboardEntry@> g_LastEntries;
string g_LastMapId = "";
int64 g_LastSubmitTime = 0;
int g_LastSubmitStatus = 0; // 0 none, 1 ok, -1 fail

void RenderFPLWindow() {
    if (!g_ShowWindow) return;
    if (UI::Begin("Friend Private Leaderboards", g_ShowWindow)) {
        UI::Text("API: " + S_API_BaseUrl);
        UI::Text("Group: " + S_GroupKey);
        UI::Separator();

        string mapId = GetCurrentMapId();
        UI::Text("Map UID: " + (mapId.Length == 0 ? "<none>" : mapId));

        if (UI::Button("Refresh Leaderboard")) {
            startnew(RefreshLeaderboardNow);
        }
        UI::SameLine();
        if (UI::Button("Submit Last Time (PB/Lap)")) {
            startnew(SubmitLastTimeNow);
        }

        if (g_LastSubmitStatus == 1) UI::Text("Last submit: OK, time=" + g_LastSubmitTime);
        else if (g_LastSubmitStatus == -1) UI::Text("Last submit: FAILED");

        UI::Separator();
        UI::Text("Leaderboard (top 10)");
        if (UI::BeginTable("fpl-lb", 3, UI::TableFlags::SizingFixedFit)) {
            UI::TableSetupColumn("#", UI::TableColumnFlags::WidthFixed, 40.0f);
            UI::TableSetupColumn("Player", UI::TableColumnFlags::WidthStretch);
            UI::TableSetupColumn("Time", UI::TableColumnFlags::WidthFixed, 90.0f);
            UI::TableHeadersRow();

            for (uint i = 0; i < g_LastEntries.Length; i++) {
                auto e = g_LastEntries[i];
                UI::TableNextRow();
                UI::TableNextColumn(); UI::Text(tostring(e.Rank));
                UI::TableNextColumn(); UI::Text(DisplayNameFor(e.AccountId));
                UI::TableNextColumn(); UI::Text(FormatTime(e.TimeMs));
            }
            UI::EndTable();
        }
    }
    UI::End();
}

void RefreshLeaderboardNow() {
    string mapId = GetCurrentMapId();
    if (mapId.Length == 0) return;
    array<LeaderboardEntry@> entries;
    if (GetLeaderboard(S_GroupKey, mapId, 10, entries)) {
        g_LastEntries = entries;
        g_LastMapId = mapId;
        ResolveLeaderboardNames();
    }
}

void SubmitLastTimeNow() {
    string mapId = GetCurrentMapId();
    if (mapId.Length == 0) return;
    int64 lastTime = GetLastRaceTimeMs();
    if (lastTime <= 0) return;
    int64 bestOut = 0;
    if (SubmitTime(S_GroupKey, GetAccountId(), mapId, lastTime, bestOut)) {
        g_LastSubmitTime = bestOut;
        g_LastSubmitStatus = 1;
        RefreshLeaderboardNow();
    } else {
        g_LastSubmitStatus = -1;
    }
}

// Get a valid time to submit. Prefer the local Personal Best via ScoreMgr.
// Returns 0 if no valid time is available.
int64 GetLastRaceTimeMs() {
    auto app = cast<CTrackMania>(GetApp());
    if (app is null) return 0;
    auto network = cast<CTrackManiaNetwork>(app.Network);
    if (network is null) return 0;
    if (network.ClientManiaAppPlayground is null) return 0;
    if (app.RootMap is null || app.RootMap.MapInfo is null) return 0;

    auto scoreMgr = network.ClientManiaAppPlayground.ScoreMgr;
    if (scoreMgr is null) return 0;
    if (network.ClientManiaAppPlayground.UserMgr is null) return 0;
    if (network.ClientManiaAppPlayground.UserMgr.Users.Length == 0) return 0;
    auto userId = network.ClientManiaAppPlayground.UserMgr.Users[0].Id;

    int timePbLocal = scoreMgr.Map_GetRecord_v2(userId, app.RootMap.MapInfo.MapUid, "PersonalBest", "", "TimeAttack", "");
    if (timePbLocal > 0) return int64(timePbLocal);

    return 0;
}

// --- Formatting helpers ---
string FormatTime(int64 ms) {
    if (ms <= 0) return "--:--.---";
    int minutes = int(ms / 60000);
    int seconds = int((ms / 1000) % 60);
    int millis = int(ms % 1000);
    return (minutes > 0
        ? (tostring(minutes) + ":" + Text::Format("%02d", seconds) + "." + Text::Format("%03d", millis))
        : (tostring(seconds) + "." + Text::Format("%03d", millis))
    );
}

// --- Name resolution integration ---
void ResolveLeaderboardNames() {
    array<string> ids;
    for (uint i = 0; i < g_LastEntries.Length; i++) ids.InsertLast(g_LastEntries[i].AccountId);
    ResolveNamesAsync(ids);
}
