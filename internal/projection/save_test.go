package projection

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestSaveDocumentsPublishesSanitizedGeneration(t *testing.T) {
	snapshot, bases, diagnostics := saveFixture(t)
	documents, err := SaveDocuments(snapshot, bases, diagnostics)
	if err != nil {
		t.Fatal(err)
	}
	if documents[len(documents)-1].Path != "data/public-save-index.json" {
		t.Fatalf("le pointeur doit être publié en dernier: %s", documents[len(documents)-1].Path)
	}
	byPath := map[string][]byte{}
	for _, document := range documents {
		byPath[document.Path] = document.Content
		if document.GenerationID == "" {
			t.Fatalf("génération absente pour %s", document.Path)
		}
	}
	if _, ok := byPath["data/players/alice.json"]; !ok {
		t.Fatal("fiche joueuse absente")
	}
	if strings.Contains(string(byPath["data/public-save-snapshot.json"]), `"key"`) {
		t.Fatal("la clé interne du joueur a été publiée")
	}
	var index map[string]any
	if err := json.Unmarshal(byPath["data/public-save-index.json"], &index); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(stringValue(index["generationId"]), "save-20260808-152629-") {
		t.Fatalf("génération inattendue: %v", index["generationId"])
	}
	players := objectSlice(index["players"])
	if len(players) != 1 || len(objectSlice(object(players[0]["pals"])["team"])) != 1 {
		t.Fatalf("index joueur incomplet: %#v", players)
	}
}

func TestSaveDocumentsRejectsTechnicalKeys(t *testing.T) {
	snapshot, bases, diagnostics := saveFixture(t)
	var decoded map[string]any
	if err := json.Unmarshal(snapshot, &decoded); err != nil {
		t.Fatal(err)
	}
	player := objectSlice(decoded["players"])[0]
	pal := objectSlice(object(player["pals"])["collection"])[0]
	pal["accountToken"] = "interdit"
	snapshot, _ = json.Marshal(decoded)
	if _, err := SaveDocuments(snapshot, bases, diagnostics); err == nil || !strings.Contains(err.Error(), "clé technique interdite") {
		t.Fatalf("clé technique acceptée: %v", err)
	}
}

func saveFixture(t *testing.T) ([]byte, []byte, []byte) {
	t.Helper()
	provenance := map[string]any{"sourceUpdatedAt": "2026-08-08T11:26:29.715399-04:00", "steamBuildId": "24466863", "schemaVersion": 5}
	snapshot := map[string]any{
		"version": 4, "ok": true, "updatedAt": "2026-08-08T11:28:34-04:00", "provenance": provenance,
		"source": map[string]any{"type": "backup", "backup": "2026.08.08-11.26.00"},
		"parser": map[string]any{"commit": "ea6592ebfbb7"}, "projection": map[string]any{"version": 5},
		"summary": map[string]any{"players": 1, "pals": 1, "guilds": 1, "bases": 1},
		"world":   map[string]any{"paldexSpecies": 1}, "guilds": []any{map[string]any{"name": "Guilde", "players": 1}},
		"players": []any{map[string]any{
			"key": "interne", "name": "Alice", "level": 80, "guild": "Guilde", "position": map[string]any{"mapX": 1},
			"character": map[string]any{"experience": 10}, "inventory": []any{},
			"pals":     map[string]any{"total": 1, "party": 1, "palbox": 0, "uniqueSpecies": 1, "highestLevel": 5, "favorites": []any{}, "collection": []any{map[string]any{"name": "Lamball", "container": "party"}}},
			"progress": map[string]any{"technologyPoints": 1, "paldex": map[string]any{"totalSpecies": 1}, "bosses": map[string]any{}, "exploration": map[string]any{}, "relics": map[string]any{}},
		}},
	}
	bases := map[string]any{
		"version": 1, "ok": true, "updatedAt": snapshot["updatedAt"], "provenance": provenance,
		"source": snapshot["source"], "parser": snapshot["parser"], "summary": map[string]any{"bases": 1},
		"bases": []any{}, "guildStorage": []any{}, "guildResearch": []any{},
	}
	diagnostics := map[string]any{
		"version": 1, "ok": true, "updatedAt": snapshot["updatedAt"], "provenance": provenance, "parser": snapshot["parser"],
		"save":  map[string]any{"backupName": "2026.08.08-11.26.00", "levelBytes": 1, "playerFiles": 1},
		"parse": map[string]any{"status": "ok", "playersParsed": 1}, "output": map[string]any{"snapshotBytes": 1},
	}
	encode := func(value any) []byte {
		content, err := json.Marshal(value)
		if err != nil {
			t.Fatal(err)
		}
		return content
	}
	return encode(snapshot), encode(bases), encode(diagnostics)
}
