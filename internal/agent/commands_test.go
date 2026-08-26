package agent

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/MathieuLF/gaylemon/internal/model"
)

func TestPalworldRestartIsRefusedByTheNonInteractiveAgent(t *testing.T) {
	command := model.Command{Kind: "service.restart", Arguments: json.RawMessage(`{"unit":"palworld.service"}`)}
	if _, err := commandArguments(command); err == nil {
		t.Fatal("le redémarrage Palworld aurait dû être refusé")
	}
	command.Arguments = json.RawMessage(`{"unit":"palworld.service","allowPalworldRestart":true}`)
	if _, err := commandArguments(command); err == nil {
		t.Fatal("le drapeau client ne doit pas remplacer une autorisation privilégiée")
	}
	if _, err := commandArguments(model.Command{Kind: "server.update", Arguments: json.RawMessage(`{}`)}); err == nil {
		t.Fatal("la mise à jour Palworld non interactive aurait dû être refusée")
	}
}

func TestSeasonArchiveUsesLifecycleTimeout(t *testing.T) {
	if got := commandTimeout("season.archive", 0); got != 75*time.Minute {
		t.Fatalf("délai de clôture: %s", got)
	}
	if got := commandTimeout("server.status", 0); got != 2*time.Minute {
		t.Fatalf("délai ordinaire: %s", got)
	}
}

func TestUnknownCommandIsRefused(t *testing.T) {
	if _, err := commandArguments(model.Command{Kind: "shell.run"}); err == nil {
		t.Fatal("une commande arbitraire aurait dû être refusée")
	}
}

func TestPauseAndResumePreserveSelectedStream(t *testing.T) {
	for _, kind := range []string{"sync.pause", "sync.resume"} {
		command := model.Command{Kind: kind, Arguments: json.RawMessage(`{"stream":"events"}`)}
		arguments, err := commandArguments(command)
		if err != nil {
			t.Fatal(err)
		}
		if len(arguments) != 3 || arguments[2] != "events" {
			t.Fatalf("le flux choisi a été perdu pour %s: %#v", kind, arguments)
		}
	}
}

func TestPauseAndResumeRefuseMissingStream(t *testing.T) {
	for _, kind := range []string{"sync.pause", "sync.resume"} {
		if _, err := commandArguments(model.Command{Kind: kind, Arguments: json.RawMessage(`{}`)}); err == nil {
			t.Fatalf("%s aurait dû refuser un flux absent", kind)
		}
	}
}

func TestSeasonCommandsAreStrictlyMapped(t *testing.T) {
	for _, kind := range []string{"season.activate", "season.archive"} {
		command := model.Command{Kind: kind, Arguments: json.RawMessage(`{"seasonId":"season-2026","slug":"saison-2026"}`)}
		arguments, err := commandArguments(command)
		if err != nil {
			t.Fatal(err)
		}
		if len(arguments) != 4 || arguments[0] != "season" || arguments[2] != "season-2026" || arguments[3] != "saison-2026" {
			t.Fatalf("mappage de %s inattendu: %#v", kind, arguments)
		}
	}
	for _, raw := range []string{`{"seasonId":"../etc","slug":"saison-2026"}`, `{"seasonId":"season-2026","slug":""}`} {
		if _, err := commandArguments(model.Command{Kind: "season.archive", Arguments: json.RawMessage(raw)}); err == nil {
			t.Fatalf("arguments dangereux acceptés: %s", raw)
		}
	}
}
