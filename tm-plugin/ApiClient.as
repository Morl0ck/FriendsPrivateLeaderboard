// Minimal Angelscript HTTP client for the private API

class LeaderboardEntry {
    string AccountId;
    string MapId;
    int64 TimeMs;
    int Rank;
}

class SubmitResp {
    int64 best_time_ms;
}

class LeaderboardResp {
    array<LeaderboardEntry@> entries;
}

string GetAccountId() {
    if (S_AccountIdOverride.Length > 0) return S_AccountIdOverride;
    auto app = GetApp();
    if (app is null || app.LocalPlayerInfo is null) return "";
    return app.LocalPlayerInfo.WebServicesUserId;
}

bool SubmitTime(const string &in groupKey, const string &in accountId, const string &in mapId, int64 timeMs, int64 &out bestTimeOut) {
    bestTimeOut = 0;
    if (S_API_BaseUrl.Length == 0) return false;
    Json::Value@ body = Json::Object();
    body["group_key"] = groupKey;
    body["account_id"] = accountId;
    body["map_id"] = mapId;
    body["time_ms"] = timeMs;
    Net::HttpRequest@ req = Net::HttpRequest();
    req.Method = Net::HttpMethod::Post;
    req.Url = S_API_BaseUrl + "/times";
    req.Body = Json::Write(body);
    req.Headers.Set("Content-Type", "application/json");
    req.Start();
    while (!req.Finished()) yield();
    if (req.ResponseCode() / 100 != 2) {
        trace("SubmitTime failed: status " + req.ResponseCode() + " body: " + req.String());
        return false;
    }
    Json::Value@ resp = Json::Parse(req.String());
    if (resp.GetType() != Json::Type::Object) return false;
    if (resp.HasKey("best_time_ms")) bestTimeOut = int64(resp["best_time_ms"]);
    return true;
}

// --- Account display name caching & resolution ---
dictionary g_NameCache; // accountId -> display name

string DisplayNameFor(const string &in accountId) {
    if (accountId.Length == 0) return "<unknown>";
    if (g_NameCache.Exists(accountId)) {
        string name;
        g_NameCache.Get(accountId, name);
        return name;
    }
    return accountId; // fallback to id until resolved
}

void ResolveNamesAsync(array<string>@ ids) {
    // Ensure authenticated to Nadeo services
    NadeoServices::AddAudience("NadeoServices");
    while (!NadeoServices::IsAuthenticated("NadeoServices")) { yield(); }

    // Batch resolve using /v2/accounts/displayNames endpoint
    // POST { accountIdList: [ ... ] }
    Json::Value@ body = Json::Object();
    Json::Value@ arr = Json::Array();
    for (uint i = 0; i < ids.Length; i++) {
        if (!g_NameCache.Exists(ids[i])) { arr.Add(ids[i]); }
    }
    if (arr.Length == 0) { return; }
    body["accountIdList"] = arr;

    auto route = "/v2/accounts/displayNames";
    Net::HttpRequest@ req = NadeoServices::Post("NadeoServices", route, Json::Write(body));
    while (!req.Finished()) { yield(); }
    if (req.ResponseCode() / 100 != 2) {
        trace("Display name fetch failed: " + req.ResponseCode() + " " + req.String());
        return;
    }
    Json::Value@ resp = Json::Parse(req.String());
    for (uint i = 0; i < resp.Length; i++) {
        auto o = resp[i];
        string id = string(o["accountId"]);
        string name = string(o["displayName"]);
        g_NameCache.Set(id, name);
    }
}

bool GetLeaderboard(const string &in groupKey, const string &in mapId, uint limit, array<LeaderboardEntry@> &out entries) {
    entries.RemoveRange(0, entries.Length);
    Net::HttpRequest@ req = Net::HttpRequest();
    req.Url = S_API_BaseUrl + "/leaderboard?group_key=" + Net::UrlEncode(groupKey) + "&map_id=" + Net::UrlEncode(mapId) + "&limit=" + limit;
    req.Start();
    while (!req.Finished()) yield();
    if (req.ResponseCode() / 100 != 2) {
        trace("GetLeaderboard failed: status " + req.ResponseCode() + " body: " + req.String());
        return false;
    }
    Json::Value@ resp = Json::Parse(req.String());
    if (resp.GetType() != Json::Type::Object || !resp.HasKey("entries")) return false;
    Json::Value@ arr = resp["entries"];
    for (uint i = 0; i < arr.Length; i++) {
        Json::Value@ o = arr[i];
        LeaderboardEntry@ e = LeaderboardEntry();
        e.AccountId = string(o["account_id"]);
        e.MapId = string(o["map_id"]);
        e.TimeMs = int64(o["time_ms"]);
        e.Rank = int(o["rank"]);
        entries.InsertLast(e);
    }
    return true;
}
