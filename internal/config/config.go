package config

import (
	"crypto/ed25519"
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type Web struct {
	ListenAddress       string
	DatabaseURL         string
	PortalRoot          string
	AssetRoot           string
	PublicBaseURL       string
	LegacyHosts         []string
	AgentPublicKeys     map[string]ed25519.PublicKey
	SignatureMaxSkew    time.Duration
	GitHubClientID      string
	GitHubClientSecret  string
	GitHubAllowedUserID int64
	CookieSecure        bool
}

func WebFromEnv() (Web, error) {
	allowedID, err := strconv.ParseInt(env("GAYLEMON_GITHUB_ALLOWED_USER_ID", "753560"), 10, 64)
	if err != nil || allowedID <= 0 {
		return Web{}, errors.New("GAYLEMON_GITHUB_ALLOWED_USER_ID doit être un entier positif")
	}
	keys, err := parseAgentKeys(os.Getenv("GAYLEMON_AGENT_PUBLIC_KEYS"))
	if err != nil {
		return Web{}, err
	}
	root, err := filepath.Abs(env("GAYLEMON_PORTAL_ROOT", "portal"))
	if err != nil {
		return Web{}, fmt.Errorf("résolution du portail: %w", err)
	}
	assets, err := filepath.Abs(env("GAYLEMON_ASSET_ROOT", "runtime/public-assets"))
	if err != nil {
		return Web{}, fmt.Errorf("résolution des assets: %w", err)
	}
	baseURL := strings.TrimRight(env("GAYLEMON_PUBLIC_BASE_URL", "http://127.0.0.1:8080"), "/")
	return Web{
		ListenAddress:       env("GAYLEMON_WEB_LISTEN", ":8080"),
		DatabaseURL:         os.Getenv("GAYLEMON_DATABASE_URL"),
		PortalRoot:          root,
		AssetRoot:           assets,
		PublicBaseURL:       baseURL,
		LegacyHosts:         csvEnv("GAYLEMON_LEGACY_HOSTS", "gaylemon.mathieu.pro,www.gaylemon.nethercore.dev"),
		AgentPublicKeys:     keys,
		SignatureMaxSkew:    durationEnv("GAYLEMON_SIGNATURE_MAX_SKEW", 5*time.Minute),
		GitHubClientID:      os.Getenv("GAYLEMON_GITHUB_CLIENT_ID"),
		GitHubClientSecret:  os.Getenv("GAYLEMON_GITHUB_CLIENT_SECRET"),
		GitHubAllowedUserID: allowedID,
		CookieSecure:        strings.HasPrefix(baseURL, "https://"),
	}, nil
}

func csvEnv(name, fallback string) []string {
	var result []string
	for _, value := range strings.Split(env(name, fallback), ",") {
		value = strings.ToLower(strings.TrimSpace(value))
		if value != "" {
			result = append(result, value)
		}
	}
	return result
}

func (c Web) Validate() error {
	if c.DatabaseURL == "" {
		return errors.New("GAYLEMON_DATABASE_URL est requis")
	}
	if len(c.AgentPublicKeys) == 0 {
		return errors.New("GAYLEMON_AGENT_PUBLIC_KEYS doit contenir au moins une clé")
	}
	return nil
}

func parseAgentKeys(raw string) (map[string]ed25519.PublicKey, error) {
	result := make(map[string]ed25519.PublicKey)
	for _, item := range strings.Split(raw, ",") {
		item = strings.TrimSpace(item)
		if item == "" {
			continue
		}
		parts := strings.SplitN(item, ":", 2)
		if len(parts) != 2 || strings.TrimSpace(parts[0]) == "" {
			return nil, fmt.Errorf("entrée GAYLEMON_AGENT_PUBLIC_KEYS invalide: %q", item)
		}
		decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(parts[1]))
		if err != nil || len(decoded) != ed25519.PublicKeySize {
			return nil, fmt.Errorf("clé Ed25519 invalide pour %s", parts[0])
		}
		result[strings.TrimSpace(parts[0])] = ed25519.PublicKey(decoded)
	}
	return result, nil
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
