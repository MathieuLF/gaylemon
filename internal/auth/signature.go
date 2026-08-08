package auth

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const (
	HeaderAgent     = "X-Gaylemon-Agent"
	HeaderTimestamp = "X-Gaylemon-Timestamp"
	HeaderNonce     = "X-Gaylemon-Nonce"
	HeaderSignature = "X-Gaylemon-Signature"
)

func BodySHA256(body []byte) string {
	sum := sha256.Sum256(body)
	return hex.EncodeToString(sum[:])
}

func Canonical(method, requestURI, timestamp, nonce, bodyHash string) []byte {
	return []byte(strings.Join([]string{strings.ToUpper(method), requestURI, timestamp, nonce, bodyHash}, "\n"))
}

func SignRequest(req *http.Request, body []byte, agentID string, privateKey ed25519.PrivateKey, now time.Time) error {
	if len(privateKey) != ed25519.PrivateKeySize {
		return errors.New("clé privée Ed25519 invalide")
	}
	nonceBytes := make([]byte, 18)
	if _, err := rand.Read(nonceBytes); err != nil {
		return fmt.Errorf("génération du nonce: %w", err)
	}
	timestamp := strconv.FormatInt(now.UTC().Unix(), 10)
	nonce := base64.RawURLEncoding.EncodeToString(nonceBytes)
	signature := ed25519.Sign(privateKey, Canonical(req.Method, req.URL.RequestURI(), timestamp, nonce, BodySHA256(body)))
	req.Header.Set(HeaderAgent, agentID)
	req.Header.Set(HeaderTimestamp, timestamp)
	req.Header.Set(HeaderNonce, nonce)
	req.Header.Set(HeaderSignature, base64.StdEncoding.EncodeToString(signature))
	return nil
}

type VerifiedRequest struct {
	AgentID   string
	Nonce     string
	ExpiresAt time.Time
}

func VerifyRequest(req *http.Request, body []byte, keys map[string]ed25519.PublicKey, now time.Time, maxSkew time.Duration) (VerifiedRequest, error) {
	agentID := strings.TrimSpace(req.Header.Get(HeaderAgent))
	key, ok := keys[agentID]
	if !ok {
		return VerifiedRequest{}, errors.New("agent inconnu")
	}
	timestampRaw := req.Header.Get(HeaderTimestamp)
	timestampUnix, err := strconv.ParseInt(timestampRaw, 10, 64)
	if err != nil {
		return VerifiedRequest{}, errors.New("horodatage invalide")
	}
	timestamp := time.Unix(timestampUnix, 0).UTC()
	if delta := now.UTC().Sub(timestamp); delta > maxSkew || delta < -maxSkew {
		return VerifiedRequest{}, errors.New("requête hors fenêtre temporelle")
	}
	nonce := strings.TrimSpace(req.Header.Get(HeaderNonce))
	if len(nonce) < 16 || len(nonce) > 128 {
		return VerifiedRequest{}, errors.New("nonce invalide")
	}
	signature, err := base64.StdEncoding.DecodeString(req.Header.Get(HeaderSignature))
	if err != nil || len(signature) != ed25519.SignatureSize {
		return VerifiedRequest{}, errors.New("signature invalide")
	}
	if !ed25519.Verify(key, Canonical(req.Method, req.URL.RequestURI(), timestampRaw, nonce, BodySHA256(body)), signature) {
		return VerifiedRequest{}, errors.New("signature refusée")
	}
	return VerifiedRequest{AgentID: agentID, Nonce: nonce, ExpiresAt: now.UTC().Add(maxSkew)}, nil
}
