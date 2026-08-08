package projection

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestPublicProjectionDropsPrivateIdentityAndSettings(t *testing.T) {
	stats := map[string]any{
		"ok": true, "players": map[string]any{"private-key": map[string]any{
			"name": "Nom public", "accountName": "PRIVATE_ACCOUNT", "playerId": "PRIVATE_ID", "isOnline": true,
			"currentSessionStartedAt": "2026-08-08T10:00:00Z", "location": map[string]any{"x": 12345.0, "y": -6789.0},
		}},
		"settings": map[string]any{"status": "available", "current": map[string]any{"Difficulty": "Normal", "PublicIP": "PRIVATE_IP", "AdminPassword": "PRIVATE_PASSWORD"}},
	}
	metrics := map[string]any{"ok": true, "players": []any{map[string]any{"name": "Nom public", "accountName": "PRIVATE_ACCOUNT"}}, "info": map[string]any{}, "metrics": map[string]any{}}
	encoded, err := json.Marshal([]any{PublicMetrics(metrics, stats), PublicStats(stats)})
	if err != nil {
		t.Fatal(err)
	}
	text := string(encoded)
	for _, forbidden := range []string{"PRIVATE_ACCOUNT", "PRIVATE_ID", "PRIVATE_IP", "PRIVATE_PASSWORD", "AdminPassword", "PublicIP"} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("valeur privée exposée: %s", forbidden)
		}
	}
	if !strings.Contains(text, "Nom public") || !strings.Contains(text, "Difficulty") {
		t.Fatalf("projection publique incomplète: %s", text)
	}
}
