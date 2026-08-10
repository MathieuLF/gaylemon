package store

import (
	"testing"
	"time"
)

func TestPublicEventFreshness(t *testing.T) {
	now := time.Date(2026, time.August, 9, 20, 0, 0, 0, time.UTC)
	tests := []struct {
		name       string
		updatedAt  time.Time
		freshness  string
		status     string
		lagSeconds int64
	}{
		{name: "current", updatedAt: now.Add(-24 * time.Minute), freshness: "current", status: "available", lagSeconds: 1440},
		{name: "stale", updatedAt: now.Add(-26 * time.Minute), freshness: "stale", status: "available", lagSeconds: 1560},
		{name: "future clock", updatedAt: now.Add(time.Minute), freshness: "current", status: "available", lagSeconds: 0},
		{name: "missing", freshness: "stale", status: "unknown", lagSeconds: 0},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			freshness, status, lagSeconds := publicEventFreshness(test.updatedAt, now)
			if freshness != test.freshness || status != test.status || lagSeconds != test.lagSeconds {
				t.Fatalf("fraîcheur inattendue: freshness=%s status=%s lag=%d", freshness, status, lagSeconds)
			}
		})
	}
}
