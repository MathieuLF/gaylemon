package auth

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"net/http"
	"testing"
	"time"
)

func TestSignAndVerifyRequest(t *testing.T) {
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	body := []byte(`{"ok":true}`)
	req, err := http.NewRequest(http.MethodPost, "https://example.test/api/ingest/v1/batches?shadow=1", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 8, 8, 12, 0, 0, 0, time.UTC)
	if err := SignRequest(req, body, "ubuntu", privateKey, now); err != nil {
		t.Fatal(err)
	}
	verified, err := VerifyRequest(req, body, map[string]ed25519.PublicKey{"ubuntu": publicKey}, now.Add(time.Minute), 5*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if verified.AgentID != "ubuntu" || verified.Nonce == "" {
		t.Fatalf("requête vérifiée inattendue: %#v", verified)
	}
}

func TestVerifyRejectsBodyChangeAndStaleTimestamp(t *testing.T) {
	publicKey, privateKey, _ := ed25519.GenerateKey(rand.Reader)
	req, _ := http.NewRequest(http.MethodPost, "https://example.test/api/ingest/v1/batches", nil)
	now := time.Now().UTC()
	if err := SignRequest(req, []byte("one"), "ubuntu", privateKey, now); err != nil {
		t.Fatal(err)
	}
	if _, err := VerifyRequest(req, []byte("two"), map[string]ed25519.PublicKey{"ubuntu": publicKey}, now, 5*time.Minute); err == nil {
		t.Fatal("une modification du corps aurait dû être refusée")
	}
	if _, err := VerifyRequest(req, []byte("one"), map[string]ed25519.PublicKey{"ubuntu": publicKey}, now.Add(6*time.Minute), 5*time.Minute); err == nil {
		t.Fatal("une requête périmée aurait dû être refusée")
	}
}
