package projection

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode"

	"github.com/MathieuLF/gaylemon/internal/model"
)

var forbiddenPublicKey = regexp.MustCompile(`(?i)uid|guid|instance|account|steam|password|token|dynamic_id`)

// SaveDocuments transforme les artefacts intermédiaires d'Ubuntu en contrat
// public. Les fichiers intermédiaires ne doivent jamais être servis tels quels.
func SaveDocuments(snapshotBytes, basesBytes, diagnosticsBytes []byte) ([]model.Document, error) {
	snapshot, err := DecodeObject(snapshotBytes)
	if err != nil {
		return nil, fmt.Errorf("snapshot invalide: %w", err)
	}
	bases, err := DecodeObject(basesBytes)
	if err != nil {
		return nil, fmt.Errorf("bases invalides: %w", err)
	}
	diagnostics, err := DecodeObject(diagnosticsBytes)
	if err != nil {
		return nil, fmt.Errorf("diagnostic invalide: %w", err)
	}
	generation, sourceUpdatedAt, err := saveGeneration(snapshot, bases, diagnostics)
	if err != nil {
		return nil, err
	}

	publicSnapshot := selectObject(snapshot, "version", "ok", "updatedAt", "provenance", "source", "parser", "projection", "summary", "world", "guilds")
	publicSnapshot["generationId"] = generation
	publicSnapshot["bases"] = []any{}
	normalizeProvenance(publicSnapshot, sourceUpdatedAt)

	players := make([]any, 0)
	playerDocuments := make([]model.Document, 0)
	seenSlugs := map[string]bool{}
	for _, rawPlayer := range objectSlice(snapshot["players"]) {
		player := publicSavePlayer(rawPlayer)
		if stringValue(player["name"]) == "" {
			continue
		}
		if err := validatePublicValue(player, "$.players[]"); err != nil {
			return nil, err
		}
		players = append(players, player)
		slug := playerSlug(stringValue(player["name"]))
		if seenSlugs[slug] {
			return nil, fmt.Errorf("deux joueurs produisent le même chemin public: %s", slug)
		}
		seenSlugs[slug] = true
		payload := map[string]any{
			"version": publicSnapshot["version"], "ok": true, "generationId": generation,
			"updatedAt": publicSnapshot["updatedAt"], "provenance": publicSnapshot["provenance"], "player": player,
		}
		content, err := json.Marshal(payload)
		if err != nil {
			return nil, err
		}
		playerDocuments = append(playerDocuments, model.Document{Path: "data/players/" + slug + ".json", Content: content, CachePolicy: model.CacheRevalidate, GenerationID: generation})
	}
	publicSnapshot["players"] = players
	if err := validatePublicValue(publicSnapshot, "$"); err != nil {
		return nil, err
	}

	publicBases := selectObject(bases, "version", "ok", "updatedAt", "provenance", "parser", "summary", "bases", "guildStorage")
	publicBases["generationId"] = generation
	normalizeProvenance(publicBases, sourceUpdatedAt)
	if err := validatePublicValue(publicBases, "$.bases"); err != nil {
		return nil, err
	}

	publicDiagnostics := publicSaveDiagnostics(diagnostics, generation, sourceUpdatedAt)
	if err := validatePublicValue(publicDiagnostics, "$.diagnostics"); err != nil {
		return nil, err
	}

	publicIndex := map[string]any{
		"version": 2, "ok": true, "generationId": generation, "updatedAt": publicSnapshot["updatedAt"],
		"provenance": publicSnapshot["provenance"], "summary": publicSnapshot["summary"], "world": publicSnapshot["world"],
		"guilds": publicSnapshot["guilds"], "players": publicSaveIndexPlayers(players),
	}
	if err := validatePublicValue(publicIndex, "$.index"); err != nil {
		return nil, err
	}

	documents := make([]model.Document, 0, 4+len(playerDocuments))
	for _, item := range []struct {
		path  string
		value any
	}{
		{"data/public-save-snapshot.json", publicSnapshot},
		{"data/public-save-bases.json", publicBases},
		{"data/public-save-diagnostics.json", publicDiagnostics},
	} {
		content, err := json.Marshal(item.value)
		if err != nil {
			return nil, err
		}
		documents = append(documents, model.Document{Path: item.path, Content: content, CachePolicy: model.CacheRevalidate, GenerationID: generation})
	}
	documents = append(documents, playerDocuments...)
	indexContent, err := json.Marshal(publicIndex)
	if err != nil {
		return nil, err
	}
	// L'index est volontairement le dernier document. Il devient le pointeur
	// visible seulement après les documents lourds et les fiches joueurs.
	documents = append(documents, model.Document{Path: "data/public-save-index.json", Content: indexContent, CachePolicy: model.CacheRevalidate, GenerationID: generation})
	return documents, nil
}

func saveGeneration(snapshot, bases, diagnostics map[string]any) (string, string, error) {
	if !boolean(snapshot["ok"]) || !boolean(bases["ok"]) || !boolean(diagnostics["ok"]) {
		return "", "", fmt.Errorf("la génération de sauvegarde est incomplète")
	}
	backup := stringValue(object(snapshot["source"])["backup"])
	if backup == "" || stringValue(object(bases["source"])["backup"]) != backup || stringValue(object(diagnostics["save"])["backupName"]) != backup {
		return "", "", fmt.Errorf("les artefacts ne décrivent pas la même sauvegarde")
	}
	provenance := object(snapshot["provenance"])
	updated := stringValue(provenance["sourceUpdatedAt"])
	if updated == "" {
		updated = stringValue(snapshot["updatedAt"])
	}
	instant, err := time.Parse(time.RFC3339Nano, updated)
	if err != nil {
		return "", "", fmt.Errorf("horodatage de sauvegarde invalide: %w", err)
	}
	instant = instant.UTC()
	parser := stringValue(object(snapshot["parser"])["commit"])
	if parser == "" || stringValue(object(bases["parser"])["commit"]) != parser || stringValue(object(diagnostics["parser"])["commit"]) != parser {
		return "", "", fmt.Errorf("les artefacts n'utilisent pas le même parseur")
	}
	projectionVersion := integer(object(snapshot["projection"])["version"])
	if projectionVersion == 0 {
		projectionVersion = integer(snapshot["version"])
	}
	instantText := fmt.Sprintf("%s.%07dZ", instant.Format("2006-01-02T15:04:05"), instant.Nanosecond()/100)
	identity := fmt.Sprintf("%s|%s|%s|%d", backup, instantText, parser, projectionVersion)
	digest := sha256.Sum256([]byte(identity))
	generation := fmt.Sprintf("save-%s-%s", instant.Format("20060102-150405"), hex.EncodeToString(digest[:8]))
	return generation, instantText, nil
}

func publicSavePlayer(raw map[string]any) map[string]any {
	player := selectObject(raw, "name", "level", "guild", "guildBases", "campLevel", "position", "character", "inventory", "progress")
	rawPals := object(raw["pals"])
	pals := selectObject(rawPals, "total", "party", "palbox", "uniqueSpecies", "highestLevel", "favorites", "collection")
	team := make([]any, 0, 5)
	for _, pal := range objectSlice(rawPals["collection"]) {
		if stringValue(pal["container"]) == "party" && len(team) < 5 {
			team = append(team, cloneValue(pal))
		}
	}
	pals["team"] = team
	player["pals"] = pals
	return player
}

func publicSaveIndexPlayers(players []any) []any {
	result := make([]any, 0, len(players))
	for _, value := range players {
		player := object(value)
		entry := selectObject(player, "name", "level", "guild", "guildBases", "campLevel", "position")
		pals := object(player["pals"])
		entry["pals"] = selectObject(pals, "total", "party", "palbox", "uniqueSpecies", "highestLevel", "favorites", "team")
		entry["progress"] = publicProgressSummary(object(player["progress"]))
		result = append(result, entry)
	}
	return result
}

func publicProgressSummary(progress map[string]any) map[string]any {
	result := selectObject(progress, "technologyPoints", "bossTechnologyPoints", "unlockedTechnologies", "completedQuests")
	result["paldex"] = selectObject(object(progress["paldex"]), "encounteredSpecies", "capturedSpecies", "totalSpecies", "totalCaptures", "captureChallengesCompleted", "completionPercent")
	result["bosses"] = selectObject(object(progress["bosses"]), "defeated", "normalDefeated", "normalKnownTotal", "towerDefeated")
	result["exploration"] = selectObject(object(progress["exploration"]), "fastTravelUnlocked", "fastTravelTotal", "areasDiscovered", "areasTotal", "worldMapsUnlocked", "completionPercent")
	result["relics"] = selectObject(object(progress["relics"]), "totalRanks", "maximumRanks", "completionPercent")
	return result
}

func publicSaveDiagnostics(raw map[string]any, generation, sourceUpdatedAt string) map[string]any {
	result := selectObject(raw, "version", "ok", "updatedAt", "provenance", "parser")
	result["generationId"] = generation
	result["save"] = selectObject(object(raw["save"]), "levelBytes", "playerFiles", "playersBytes", "generationBytes", "backupAgeSeconds")
	parse := selectObject(object(raw["parse"]), "durationMs", "decodeDurationMs", "projectionDurationMs", "status", "warnings", "playersParsed", "palsParsed", "basesParsed", "unknownStructures", "catalogDrift")
	result["parse"] = parse
	result["output"] = selectObject(object(raw["output"]), "snapshotBytes", "snapshotGzipBytes", "basesBytes", "basesGzipBytes", "privateBasesBytes", "historyArchiveBytes", "basesHistoryArchiveBytes")
	normalizeProvenance(result, sourceUpdatedAt)
	return result
}

func normalizeProvenance(root map[string]any, sourceUpdatedAt string) {
	provenance := cloneValue(object(root["provenance"])).(map[string]any)
	provenance["sourceUpdatedAt"] = sourceUpdatedAt
	root["provenance"] = provenance
}

func selectObject(source map[string]any, fields ...string) map[string]any {
	result := make(map[string]any, len(fields))
	for _, field := range fields {
		if value, found := source[field]; found {
			result[field] = cloneValue(value)
		}
	}
	return result
}

func cloneValue(value any) any {
	if value == nil {
		return nil
	}
	content, _ := json.Marshal(value)
	var cloned any
	_ = json.Unmarshal(content, &cloned)
	return cloned
}

func validatePublicValue(value any, path string) error {
	switch typed := value.(type) {
	case map[string]any:
		keys := make([]string, 0, len(typed))
		for key := range typed {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			if key != "container" && key != "steamBuildId" && forbiddenPublicKey.MatchString(key) {
				return fmt.Errorf("clé technique interdite dans la projection publique: %s.%s", path, key)
			}
			if err := validatePublicValue(typed[key], path+"."+key); err != nil {
				return err
			}
		}
	case []any:
		for index, item := range typed {
			if err := validatePublicValue(item, fmt.Sprintf("%s[%d]", path, index)); err != nil {
				return err
			}
		}
	}
	return nil
}

func playerSlug(name string) string {
	replacer := strings.NewReplacer("à", "a", "á", "a", "â", "a", "ä", "a", "ã", "a", "å", "a", "ç", "c", "è", "e", "é", "e", "ê", "e", "ë", "e", "ì", "i", "í", "i", "î", "i", "ï", "i", "ñ", "n", "ò", "o", "ó", "o", "ô", "o", "ö", "o", "õ", "o", "ù", "u", "ú", "u", "û", "u", "ü", "u", "ý", "y", "ÿ", "y", "œ", "oe", "æ", "ae")
	normalized := replacer.Replace(strings.ToLower(strings.TrimSpace(name)))
	var builder strings.Builder
	dash := false
	for _, character := range normalized {
		if character <= unicode.MaxASCII && (unicode.IsLetter(character) || unicode.IsDigit(character)) {
			builder.WriteRune(character)
			dash = false
		} else if builder.Len() > 0 && !dash {
			builder.WriteByte('-')
			dash = true
		}
	}
	return strings.Trim(builder.String(), "-")
}
