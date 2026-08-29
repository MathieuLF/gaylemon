package store

import (
	"encoding/json"
	"testing"
)

func TestEscapeLikePatternTreatsWildcardsAsText(t *testing.T) {
	got := escapeLikePattern(`100%_ready\now`)
	want := `100\%\_ready\\now`
	if got != want {
		t.Fatalf("motif LIKE mal échappé: got=%q want=%q", got, want)
	}
	if escapeLikePattern("ordinary search") != "ordinary search" {
		t.Fatal("une recherche ordinaire ne doit pas être modifiée")
	}
}

func TestSeasonArchiveProofRequiresImmutableBackupAndReceipt(t *testing.T) {
	valid := json.RawMessage(`{"seasonId":"season-2026","slug":"saison-2026","immutableBackup":"urn:gaylemon:season-archive:saison-2026:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","backupSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receipt":"urn:gaylemon:season-receipt:saison-2026:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receiptSha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","queueDepth":0,"palworldPid":"4242","palworldRestarts":"0"}`)
	if err := validateSeasonArchiveProof(valid, "season-2026", "saison-2026"); err != nil {
		t.Fatalf("preuve valide refusée: %v", err)
	}
	for name, raw := range map[string]string{
		"mauvaise saison":     `{"seasonId":"autre","slug":"saison-2026","immutableBackup":"urn:gaylemon:season-archive:saison-2026:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","backupSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receipt":"urn:gaylemon:season-receipt:saison-2026:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receiptSha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","queueDepth":0,"palworldPid":"4242","palworldRestarts":"0"}`,
		"sauvegarde mutable":  `{"seasonId":"season-2026","slug":"saison-2026","immutableBackup":"urn:other:season-archive:saison-2026:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","backupSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receipt":"urn:gaylemon:season-receipt:saison-2026:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receiptSha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","queueDepth":0,"palworldPid":"4242","palworldRestarts":"0"}`,
		"file non vide":       `{"seasonId":"season-2026","slug":"saison-2026","immutableBackup":"urn:gaylemon:season-archive:saison-2026:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","backupSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receipt":"urn:gaylemon:season-receipt:saison-2026:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receiptSha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","queueDepth":1,"palworldPid":"4242","palworldRestarts":"0"}`,
		"traversée de chemin": `{"seasonId":"season-2026","slug":"saison-2026","immutableBackup":"urn:gaylemon:season-archive:saison-2026/..:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","backupSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receipt":"urn:gaylemon:season-receipt:saison-2026:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","receiptSha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","queueDepth":0,"palworldPid":"4242","palworldRestarts":"0"}`,
	} {
		t.Run(name, func(t *testing.T) {
			if err := validateSeasonArchiveProof(json.RawMessage(raw), "season-2026", "saison-2026"); err == nil {
				t.Fatal("preuve incomplète acceptée")
			}
		})
	}
}

func TestSeasonActivateProofIsBoundToSeasonAndPalworldInvariant(t *testing.T) {
	valid := json.RawMessage(`{"seasonId":"season-2027","slug":"saison-2027","activated":true,"palworldPid":"4242","palworldRestarts":"0"}`)
	if err := validateSeasonActivateProof(valid, "season-2027", "saison-2027"); err != nil {
		t.Fatalf("preuve valide refusée: %v", err)
	}
	for _, raw := range []string{
		`{"seasonId":"season-2026","slug":"saison-2027","activated":true,"palworldPid":"4242","palworldRestarts":"0"}`,
		`{"seasonId":"season-2027","slug":"saison-2027","activated":false,"palworldPid":"4242","palworldRestarts":"0"}`,
		`{"seasonId":"season-2027","slug":"saison-2027","activated":true,"palworldPid":"0","palworldRestarts":"0"}`,
	} {
		if err := validateSeasonActivateProof(json.RawMessage(raw), "season-2027", "saison-2027"); err == nil {
			t.Fatalf("preuve incohérente acceptée: %s", raw)
		}
	}
}
