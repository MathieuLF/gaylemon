package config

import "testing"

func TestWebFromEnvRequiresExplicitGitHubIdentity(t *testing.T) {
	t.Setenv("GAYLEMON_AGENT_PUBLIC_KEYS", "")
	t.Setenv("GAYLEMON_RESPONSE_PRIVATE_KEY", "")
	for _, value := range []string{"", "0", "-1", "invalid"} {
		t.Run("reject_"+value, func(t *testing.T) {
			t.Setenv("GAYLEMON_GITHUB_ALLOWED_USER_ID", value)
			if _, err := WebFromEnv(); err == nil {
				t.Fatal("une installation sans identité explicite valide doit être refusée")
			}
		})
	}
	t.Setenv("GAYLEMON_GITHUB_ALLOWED_USER_ID", "42")
	settings, err := WebFromEnv()
	if err != nil || settings.GitHubAllowedUserID != 42 {
		t.Fatalf("identité fournie non conservée: id=%d, erreur=%v", settings.GitHubAllowedUserID, err)
	}
}
