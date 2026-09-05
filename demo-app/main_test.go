package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type fakeDatabase struct {
	readyErr error
	checkErr error
}

func (db fakeDatabase) Ready(context.Context) error { return db.readyErr }
func (db fakeDatabase) Check(context.Context) error { return db.checkErr }

func TestHealthz(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	response := httptest.NewRecorder()

	newHandler(fakeDatabase{}).ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("expected %d, got %d", http.StatusOK, response.Code)
	}
}

func TestMetrics(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	response := httptest.NewRecorder()

	newHandler(fakeDatabase{}).ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("expected %d, got %d", http.StatusOK, response.Code)
	}
	if !strings.Contains(response.Body.String(), "go_goroutines") {
		t.Fatal("expected Go runtime metrics")
	}
}

func TestReadyz(t *testing.T) {
	tests := []struct {
		name       string
		database   fakeDatabase
		wantStatus int
	}{
		{name: "ready", database: fakeDatabase{}, wantStatus: http.StatusOK},
		{name: "database unavailable", database: fakeDatabase{readyErr: errors.New("down")}, wantStatus: http.StatusServiceUnavailable},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodGet, "/readyz", nil)
			response := httptest.NewRecorder()
			newHandler(tt.database).ServeHTTP(response, request)
			if response.Code != tt.wantStatus {
				t.Fatalf("expected %d, got %d", tt.wantStatus, response.Code)
			}
		})
	}
}

func TestDatabaseEndpoint(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/db", nil)
	response := httptest.NewRecorder()
	newHandler(fakeDatabase{}).ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("expected %d, got %d", http.StatusOK, response.Code)
	}
}
