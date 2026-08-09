package agent

import (
	"encoding/json"
	"testing"

	"github.com/MathieuLF/gaylemon/internal/model"
)

func TestPalworldRestartRequiresExplicitFlag(t *testing.T) {
	command := model.Command{Kind: "service.restart", Arguments: json.RawMessage(`{"unit":"palworld.service"}`)}
	if _, err := commandArguments(command); err == nil {
		t.Fatal("le redémarrage Palworld aurait dû être refusé")
	}
	command.Arguments = json.RawMessage(`{"unit":"palworld.service","allowPalworldRestart":true}`)
	arguments, err := commandArguments(command)
	if err != nil {
		t.Fatal(err)
	}
	if len(arguments) != 3 || arguments[0] != "restart" {
		t.Fatalf("arguments inattendus: %#v", arguments)
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
