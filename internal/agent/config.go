package agent

import (
	"crypto/ed25519"
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type Config struct {
	AgentID           string
	APIBaseURL        string
	PrivateKey        ed25519.PrivateKey
	ResponsePublicKey ed25519.PublicKey
	SpoolPath         string
	CommandHelper     string
	CommandSudo       bool
	HTTPTimeout       time.Duration
	PollInterval      time.Duration
	Profile           string
	Shadow            bool
}

func ConfigFromEnv() (Config, error) {
	key, err := loadPrivateKey(strings.TrimSpace(os.Getenv("GAYLEMON_AGENT_PRIVATE_KEY_FILE")))
	if err != nil {
		return Config{}, err
	}
	responseKey, err := loadPublicKey(strings.TrimSpace(os.Getenv("GAYLEMON_RESPONSE_PUBLIC_KEY")))
	if err != nil {
		return Config{}, err
	}
	spool := env("GAYLEMON_AGENT_SPOOL", "runtime/agent-spool.db")
	if absolute, err := filepath.Abs(spool); err == nil {
		spool = absolute
	}
	return Config{
		AgentID:           env("GAYLEMON_AGENT_ID", "palworld-ubuntu"),
		APIBaseURL:        strings.TrimRight(os.Getenv("GAYLEMON_API_BASE_URL"), "/"),
		PrivateKey:        key,
		ResponsePublicKey: responseKey,
		SpoolPath:         spool,
		CommandHelper:     env("GAYLEMON_COMMAND_HELPER", ""),
		CommandSudo:       boolEnv("GAYLEMON_COMMAND_SUDO", false),
		HTTPTimeout:       durationEnv("GAYLEMON_AGENT_HTTP_TIMEOUT", 60*time.Second),
		PollInterval:      durationEnv("GAYLEMON_AGENT_POLL_INTERVAL", 15*time.Second),
		Profile:           env("GAYLEMON_AGENT_PROFILE", "ubuntu-palworld"),
		Shadow:            boolEnv("GAYLEMON_AGENT_SHADOW", true),
	}, nil
}

func boolEnv(name string, fallback bool) bool {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(name)))
	if value == "" {
		return fallback
	}
	return value == "1" || value == "true" || value == "yes"
}

func (c Config) Validate() error {
	if strings.TrimSpace(c.AgentID) == "" {
		return errors.New("GAYLEMON_AGENT_ID est requis")
	}
	if !strings.HasPrefix(c.APIBaseURL, "https://") && !strings.HasPrefix(c.APIBaseURL, "http://127.0.0.1") {
		return errors.New("GAYLEMON_API_BASE_URL doit utiliser HTTPS")
	}
	if len(c.PrivateKey) != ed25519.PrivateKeySize {
		return errors.New("GAYLEMON_AGENT_PRIVATE_KEY_FILE doit contenir une clé Ed25519")
	}
	if strings.HasPrefix(c.APIBaseURL, "https://") && len(c.ResponsePublicKey) != ed25519.PublicKeySize {
		return errors.New("GAYLEMON_RESPONSE_PUBLIC_KEY est requis avec l'API HTTPS")
	}
	return nil
}

func loadPublicKey(raw string) (ed25519.PublicKey, error) {
	if raw == "" {
		return nil, nil
	}
	decoded, err := base64.StdEncoding.DecodeString(raw)
	if err != nil || len(decoded) != ed25519.PublicKeySize {
		return nil, errors.New("GAYLEMON_RESPONSE_PUBLIC_KEY est invalide")
	}
	return ed25519.PublicKey(decoded), nil
}

func loadPrivateKey(path string) (ed25519.PrivateKey, error) {
	if path == "" {
		return nil, errors.New("GAYLEMON_AGENT_PRIVATE_KEY_FILE est requis")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("lecture de la clé privée: %w", err)
	}
	decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(raw)))
	if err != nil {
		return nil, errors.New("la clé privée doit être encodée en base64")
	}
	if len(decoded) == ed25519.SeedSize {
		return ed25519.NewKeyFromSeed(decoded), nil
	}
	if len(decoded) != ed25519.PrivateKeySize {
		return nil, errors.New("taille de clé privée Ed25519 invalide")
	}
	return ed25519.PrivateKey(decoded), nil
}

func env(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

func durationEnv(name string, fallback time.Duration) time.Duration {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}
