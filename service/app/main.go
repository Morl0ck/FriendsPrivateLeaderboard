package main

import (
    "context"
    "encoding/json"
    "errors"
    "log"
    "net/http"
    "os"
    "strconv"
    "time"

    "github.com/go-chi/chi/v5"
    "github.com/go-chi/chi/v5/middleware"
    "github.com/jackc/pgx/v5/pgxpool"
)

type Server struct {
    db *pgxpool.Pool
}

type SubmitTimeRequest struct {
    GroupKey  string `json:"group_key"`
    AccountID string `json:"account_id"`
    MapID     string `json:"map_id"`
    TimeMs    int64  `json:"time_ms"`
}

type LeaderboardEntry struct {
    AccountID string `json:"account_id"`
    MapID     string `json:"map_id"`
    TimeMs    int64  `json:"time_ms"`
    Rank      int    `json:"rank"`
}

func main() {
    ctx := context.Background()
    dsn := os.Getenv("DATABASE_URL")
    if dsn == "" {
        // default for local compose
        dsn = "postgres://fpl_user:fpl_password@db:5432/friend_leaderboards?sslmode=disable"
    }

    cfg, err := pgxpool.ParseConfig(dsn)
    if err != nil {
        log.Fatalf("invalid DATABASE_URL: %v", err)
    }
    cfg.MaxConns = 8
    pool, err := pgxpool.NewWithConfig(ctx, cfg)
    if err != nil {
        log.Fatalf("failed to connect to database: %v", err)
    }
    defer pool.Close()

    if err := migrate(ctx, pool); err != nil {
        log.Fatalf("migration failed: %v", err)
    }

    s := &Server{db: pool}

    r := chi.NewRouter()
    r.Use(middleware.RequestID)
    r.Use(middleware.RealIP)
    r.Use(middleware.Logger)
    r.Use(middleware.Recoverer)

    r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
        if err := pool.Ping(r.Context()); err != nil {
            http.Error(w, "db not ready", http.StatusServiceUnavailable)
            return
        }
        w.WriteHeader(http.StatusOK)
        w.Write([]byte("ok"))
    })

    r.Post("/times", s.handleSubmitTime)
    r.Get("/leaderboard", s.handleGetLeaderboard)

    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    srv := &http.Server{Addr: ":" + port, Handler: r}
    log.Printf("listening on :%s", port)
    log.Fatal(srv.ListenAndServe())
}

func migrate(ctx context.Context, pool *pgxpool.Pool) error {
    if _, err := pool.Exec(ctx, `
        CREATE TABLE IF NOT EXISTS times (
            group_key  TEXT NOT NULL,
            account_id TEXT NOT NULL,
            map_id     TEXT NOT NULL,
            time_ms    BIGINT NOT NULL CHECK (time_ms > 0),
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            PRIMARY KEY (group_key, map_id, account_id)
        );
    `); err != nil {
        return err
    }
    if _, err := pool.Exec(ctx, `
        CREATE INDEX IF NOT EXISTS idx_times_group_map_time ON times(group_key, map_id, time_ms);
    `); err != nil {
        return err
    }
    return nil
}

func (s *Server) handleSubmitTime(w http.ResponseWriter, r *http.Request) {
    var req SubmitTimeRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, "invalid json", http.StatusBadRequest)
        return
    }
    if req.GroupKey == "" || req.AccountID == "" || req.MapID == "" || req.TimeMs <= 0 {
        http.Error(w, "missing required fields", http.StatusBadRequest)
        return
    }

    ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
    defer cancel()

    // Upsert keeping best (lowest) time
    // If existing time is better, keep; else update.
    cmd := `
        INSERT INTO times (group_key, account_id, map_id, time_ms)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (group_key, map_id, account_id)
        DO UPDATE SET time_ms = LEAST(EXCLUDED.time_ms, times.time_ms), updated_at = now()
        RETURNING time_ms;
    `

    var best int64
    if err := s.db.QueryRow(ctx, cmd, req.GroupKey, req.AccountID, req.MapID, req.TimeMs).Scan(&best); err != nil {
        http.Error(w, "db error", http.StatusInternalServerError)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]any{"best_time_ms": best})
}

func (s *Server) handleGetLeaderboard(w http.ResponseWriter, r *http.Request) {
    groupKey := r.URL.Query().Get("group_key")
    mapID := r.URL.Query().Get("map_id")
    if groupKey == "" || mapID == "" {
        http.Error(w, "group_key and map_id are required", http.StatusBadRequest)
        return
    }
    limit := 50
    if v := r.URL.Query().Get("limit"); v != "" {
        if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 500 {
            limit = n
        }
    }

    ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
    defer cancel()

    rows, err := s.db.Query(ctx, `
        SELECT account_id, map_id, time_ms,
               ROW_NUMBER() OVER (ORDER BY time_ms ASC, account_id ASC) AS rank
        FROM times
        WHERE group_key = $1 AND map_id = $2
        ORDER BY time_ms ASC, account_id ASC
        LIMIT $3;
    `, groupKey, mapID, limit)
    if err != nil {
        http.Error(w, "db error", http.StatusInternalServerError)
        return
    }
    defer rows.Close()

    res := make([]LeaderboardEntry, 0, limit)
    for rows.Next() {
        var e LeaderboardEntry
        if err := rows.Scan(&e.AccountID, &e.MapID, &e.TimeMs, &e.Rank); err != nil {
            http.Error(w, "db error", http.StatusInternalServerError)
            return
        }
        res = append(res, e)
    }
    if err := rows.Err(); err != nil && !errors.Is(err, context.Canceled) {
        http.Error(w, "db error", http.StatusInternalServerError)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]any{"entries": res})
}
