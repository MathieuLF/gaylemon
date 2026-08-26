package agent

import (
	"bytes"
	"compress/gzip"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"io"
	"net/http"
	"testing"
	"time"
)

func TestCompressJSONBodyKeepsSmallRequestsAndCompressesLargeOnes(t *testing.T) {
	small := []byte(`{"ok":true}`)
	wire, encoding, err := compressJSONBody(small)
	if err != nil || encoding != "" || !bytes.Equal(wire, small) {
		t.Fatalf("petit corps modifié: encoding=%q err=%v", encoding, err)
	}

	large := bytes.Repeat([]byte(`{"event":"Fabrications terminées"}`), 4096)
	wire, encoding, err = compressJSONBody(large)
	if err != nil || encoding != "gzip" || len(wire) >= len(large)/4 {
		t.Fatalf("compression inefficace: raw=%d wire=%d encoding=%q err=%v", len(large), len(wire), encoding, err)
	}
	reader, err := gzip.NewReader(bytes.NewReader(wire))
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := io.ReadAll(reader)
	if err != nil || !bytes.Equal(decoded, large) {
		t.Fatalf("corps compressé altéré: err=%v", err)
	}
}

func TestSeasonArchivedResponseRequiresValidFreshSignature(t *testing.T) {
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	client := &Client{config: Config{ResponsePublicKey: publicKey}}
	body := []byte("{\"error\":\"season-archived\",\"ok\":false}\n")
	now := time.Now().UTC()
	timestamp := now.Format(time.RFC3339Nano)
	digest := sha256.Sum256(body)
	message := timestamp + "\n423\n" + hex.EncodeToString(digest[:])
	response := &http.Response{Header: make(http.Header)}
	response.Header.Set("X-Gaylemon-Season-State", "archived")
	response.Header.Set("X-Gaylemon-Response-Timestamp", timestamp)
	response.Header.Set("X-Gaylemon-Response-Signature", base64.StdEncoding.EncodeToString(ed25519.Sign(privateKey, []byte(message))))
	if err := client.verifySeasonLocked(response, body, now); err != nil {
		t.Fatal(err)
	}
	body[5] ^= 1
	if err := client.verifySeasonLocked(response, body, now); err == nil {
		t.Fatal("un corps altéré a été accepté")
	}
}
