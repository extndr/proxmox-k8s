package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	version = "dev"
	commit  = "unknown"
)

type database interface {
	Ready(context.Context) error
	Check(context.Context) error
}

type postgresDB struct {
	pool *pgxpool.Pool
}

func (db postgresDB) Ready(ctx context.Context) error {
	return db.pool.Ping(ctx)
}

func (db postgresDB) Check(ctx context.Context) error {
	var value int
	if err := db.pool.QueryRow(ctx, "select 1").Scan(&value); err != nil {
		return err
	}
	if value != 1 {
		return fmt.Errorf("unexpected database response: %d", value)
	}
	return nil
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	databaseURL, err := buildDatabaseURL()
	if err != nil {
		logger.Error("invalid configuration", "error", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		logger.Error("create database pool", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	server := &http.Server{
		Addr:              envOrDefault("LISTEN_ADDRESS", ":8080"),
		Handler:           newHandler(postgresDB{pool: pool}),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	serverErrors := make(chan error, 1)
	go func() {
		logger.Info("server started", "address", server.Addr, "version", version, "commit", commit)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErrors <- err
			return
		}
		serverErrors <- nil
	}()

	select {
	case err := <-serverErrors:
		if err != nil {
			logger.Error("server failed", "error", err)
			os.Exit(1)
		}
	case <-ctx.Done():
		logger.Info("shutdown requested")
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		logger.Error("graceful shutdown failed", "error", err)
		os.Exit(1)
	}
}

func buildDatabaseURL() (string, error) {
	password := os.Getenv("DB_PASSWORD")
	if password == "" {
		return "", errors.New("DB_PASSWORD is required")
	}

	databaseURL := &url.URL{
		Scheme: "postgres",
		User:   url.UserPassword(envOrDefault("DB_USER", "lab"), password),
		Host:   net.JoinHostPort(envOrDefault("DB_HOST", "postgres"), envOrDefault("DB_PORT", "5432")),
		Path:   envOrDefault("DB_NAME", "lab"),
	}
	query := databaseURL.Query()
	query.Set("sslmode", envOrDefault("DB_SSLMODE", "disable"))
	databaseURL.RawQuery = query.Encode()

	return databaseURL.String(), nil
}

func envOrDefault(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func newHandler(db database) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), time.Second)
		defer cancel()
		if err := db.Ready(ctx); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not ready"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
	})

	mux.HandleFunc("GET /db", func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := db.Check(ctx); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"database": "unavailable"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"database":   "ok",
			"latency_ms": time.Since(started).Milliseconds(),
		})
	})

	mux.HandleFunc("GET /version", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{
			"version": version,
			"commit":  commit,
		})
	})

	return mux
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
