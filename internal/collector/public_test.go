package collector

import (
	"os"
	"path/filepath"
	"testing"
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
