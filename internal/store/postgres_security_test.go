package store

import "testing"

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
