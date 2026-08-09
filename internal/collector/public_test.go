package collector

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPublicEventsFingerprintTracksExactContent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "public-events.json")
	first := `{"revision":"events-42","events":[{"key":"craft:42"}]}`
	if err := os.WriteFile(path, []byte(first), 0o600); err != nil {
		t.Fatal(err)
	}
	fingerprint, err := PublicEventsFingerprint(path)
	if err != nil || !strings.HasPrefix(fingerprint, "events-42:sha256:") {
		t.Fatalf("empreinte inattendue: %q err=%v", fingerprint, err)
	}
	if err := os.WriteFile(path, []byte(strings.Replace(first, "craft:42", "craft:43", 1)), 0o600); err != nil {
		t.Fatal(err)
	}
	changed, err := PublicEventsFingerprint(path)
	if err != nil || changed == fingerprint {
		t.Fatalf("modification non détectée: first=%q changed=%q err=%v", fingerprint, changed, err)
	}
}
