# Trackmania Friend Leaderboards Service

This service exposes a simple HTTP API for submitting and querying Trackmania leaderboard times grouped by `group_key`.

## API

- POST /times

  - Body: `{ "group_key": "g1", "account_id": "acc123", "map_id": "mapABC", "time_ms": 65432 }`
  - Upserts the user's best time (lowest) for a given group and map.
  - Response: `{ "best_time_ms": 65432 }`

- GET /leaderboard?group_key=g1&map_id=mapABC&limit=50

  - Response: `{ "entries": [{ "account_id": "acc123", "map_id": "mapABC", "time_ms": 65432, "rank": 1 }] }`

- GET /health
  - Returns `ok` when the API and DB are reachable.

## Running with Docker Compose

Ensure Docker Desktop is running.

```powershell
# from repo root or service folder
# builds the API image and starts API + Postgres
docker compose -f service/docker-compose.yaml up --build -d
```

The API will listen on http://localhost:8080.

## Environment

- `DATABASE_URL` (optional): defaults to `postgres://fpl_user:fpl_password@db:5432/friend_leaderboards?sslmode=disable` when running in compose.
- `PORT` (optional): defaults to `8080`.

## Notes

- Data is stored in Postgres with a primary key on (group_key, map_id, account_id). On upsert, the best (lowest) time is kept.
- Migrations are minimal and run at startup.
