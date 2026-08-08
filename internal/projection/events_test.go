package projection

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"
	"testing"
)

func TestEventsV6BuildsSelfConsistentContracts(t *testing.T) {
	source := map[string]any{
		"revision":   "6:test:2:42",
		"updatedAt":  "2026-08-08T10:10:00-04:00",
		"provenance": map[string]any{"sourceUpdatedAt": "2026-08-08T10:10:00-04:00", "sourceStatus": "available", "freshness": "current"},
		"summary":    map[string]any{"rawEvents": 3, "publicEvents": 2, "representedEvents": 3},
		"events": []any{
			map[string]any{"key": "level:alice:2", "id": 42, "occurredAt": "2026-08-08T10:00:00-04:00", "type": "level", "player": "Alice", "confidence": "confirmed", "details": map[string]any{"aggregatedEvents": 2}},
			map[string]any{"key": "capture:alice:pal", "id": 41, "occurredAt": "2026-08-08T09:00:00-04:00", "type": "capture", "player": "Alice", "confidence": "derived", "details": map[string]any{}},
		},
	}
	documents, err := EventsV6(source)
	if err != nil {
		t.Fatal(err)
	}
	byPath := map[string][]byte{}
	for _, document := range documents {
		byPath[document.Path] = document.Content
	}
	var pointer map[string]any
	if err := json.Unmarshal(byPath["data/public-events-head-v6.json"], &pointer); err != nil {
		t.Fatal(err)
	}
	manifestReference := object(pointer["manifest"])
	manifestPath := stringValue(manifestReference["path"])
	manifestBytes := byPath[manifestPath]
	if len(manifestBytes) == 0 {
		t.Fatalf("manifeste immuable absent: %s", manifestPath)
	}
	digest := sha256.Sum256(manifestBytes)
	if stringValue(manifestReference["sha256"]) != "sha256:"+hex.EncodeToString(digest[:]) {
		t.Fatal("hachage du manifeste incohérent")
	}
	var manifest map[string]any
	if err := json.Unmarshal(manifestBytes, &manifest); err != nil {
		t.Fatal(err)
	}
	days, ok := manifest["days"].([]any)
	if !ok || len(days) != 1 {
		t.Fatalf("jours inattendus: %#v", manifest["days"])
	}
	entry := object(days[0])
	if len(byPath[stringValue(entry["path"])]) == 0 || len(byPath[stringValue(entry["dailyPath"])]) == 0 {
		t.Fatal("fragment ou bilan quotidien absent")
	}
	if string(byPath["public-events-channel.json"]) != `{"schemaVersion":1,"activeContract":"v6","candidateContract":"v6"}` {
		t.Fatal("canal v6 inattendu")
	}
}

func TestEventsV6RejectsPrivateFields(t *testing.T) {
	source := map[string]any{"events": []any{map[string]any{"key": "bad", "id": 1, "occurredAt": "2026-08-08T10:00:00-04:00", "type": "note", "accountName": "private"}}}
	if _, err := EventsV6(source); err == nil || !strings.Contains(err.Error(), "privé") {
		t.Fatalf("champ privé accepté: %v", err)
	}
}
