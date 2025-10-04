// Simple settings for the Friend Private Leaderboards plugin

[Setting category="Friend Private Leaderboards" name="API Base URL" description="Base URL to the private API (e.g., http://localhost:8080)"]
string S_API_BaseUrl = "http://localhost:8080";

[Setting category="Friend Private Leaderboards" name="Group Key" description="Group key to use when submitting and querying leaderboards"]
string S_GroupKey = "friends1";

[Setting category="Friend Private Leaderboards" name="Account ID (override)" description="Optional override for account id; leave empty to use your own account id"]
string S_AccountIdOverride = "";

void LoadSettings() {}
