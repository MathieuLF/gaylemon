package collector

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestPublicEventsRevisionReadsHeaderWithoutLoadingEvents(t *testing.T) {
	path := filepath.Join(t.TempDir(), "public-events.json")
	first := `{"revision":"events-42","events":[{"key":"craft:42"}]}`
	if err := os.WriteFile(path, []byte(first), 0o600); err != nil {
		t.Fatal(err)
	}
	revision, err := PublicEventsRevision(path)
	if err != nil || revision != "events-42" {
		t.Fatalf("révision inattendue: %q err=%v", revision, err)
	}

	invalidPath := filepath.Join(t.TempDir(), "invalid.json")
	if err := os.WriteFile(invalidPath, []byte(`{"events":[]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := PublicEventsRevision(invalidPath); err == nil {
		t.Fatal("une enveloppe sans révision devrait être refusée")
	}
}

func TestPublicEventsObservedAtRequiresACompleteCollectorReport(t *testing.T) {
	path := filepath.Join(t.TempDir(), "recovery.json")
	if err := os.WriteFile(path, []byte(`{"ok":true,"status":"complete","checkedAt":"2026-08-09T20:08:25.379110-04:00"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	observedAt, err := PublicEventsObservedAt(path)
	if err != nil || observedAt.Format(time.RFC3339Nano) != "2026-08-09T20:08:25.37911-04:00" {
		t.Fatalf("observation inattendue: %s err=%v", observedAt, err)
	}
	if err := os.WriteFile(path, []byte(`{"ok":false,"status":"error","checkedAt":"2026-08-09T20:09:00-04:00"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := PublicEventsObservedAt(path); err == nil {
		t.Fatal("une collecte incomplète ne doit pas rafraîchir l'observation")
	}
}
