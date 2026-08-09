package projection

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/MathieuLF/gaylemon/internal/model"
)

const eventHeadLimit = 7

var (
	privateEventKey = regexp.MustCompile(`(?i)^(?:ip|ipaddress|address|host|hostname|port|endpoint|url|uri|uid|guid|instance|container|account(?:name)?|playerid|userid|steam(?:id)?|password|token|dynamic_id|position|coordinates?|map[xyz]|world[xyz])$`)
	ipv4Literal     = regexp.MustCompile(`(?:^|[^0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:[^0-9]|$)`)
)

// ValidatePublicEvents vérifie le contrat complet sans matérialiser tout le
// journal en maps Go. Un seul écho est décodé à la fois, ce qui garde la
// validation de confidentialité tout en bornant la mémoire du collecteur.
func ValidatePublicEvents(content []byte) (string, int, error) {
	decoder := json.NewDecoder(bytes.NewReader(content))
	opening, err := decoder.Token()
	if err != nil || opening != json.Delim('{') {
		return "", 0, errors.New("journal public invalide")
	}
	revision := ""
	eventCount := 0
	for decoder.More() {
		keyToken, err := decoder.Token()
		if err != nil {
			return "", 0, fmt.Errorf("lecture du journal public: %w", err)
		}
		key, ok := keyToken.(string)
		if !ok {
			return "", 0, errors.New("clé de journal public invalide")
		}
		switch key {
		case "revision":
			if err := decoder.Decode(&revision); err != nil {
				return "", 0, errors.New("révision du journal public invalide")
			}
		case "events":
			openingEvents, err := decoder.Token()
			if err != nil || openingEvents != json.Delim('[') {
				return "", 0, errors.New("liste des échos publics invalide")
			}
			for decoder.More() {
				var event map[string]any
				if err := decoder.Decode(&event); err != nil {
					return "", 0, fmt.Errorf("écho public invalide: %w", err)
				}
				if err := validatePublicEvent(event); err != nil {
					return "", 0, err
				}
				eventCount++
			}
			if closingEvents, err := decoder.Token(); err != nil || closingEvents != json.Delim(']') {
				return "", 0, errors.New("fin de liste des échos publics invalide")
			}
		default:
			var discarded json.RawMessage
			if err := decoder.Decode(&discarded); err != nil {
				return "", 0, fmt.Errorf("champ public %s invalide: %w", key, err)
			}
		}
	}
	if closing, err := decoder.Token(); err != nil || closing != json.Delim('}') {
		return "", 0, errors.New("fin du journal public invalide")
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return "", 0, errors.New("contenu présent après le journal public")
	}
	if strings.TrimSpace(revision) == "" {
		return "", 0, errors.New("révision du journal public absente")
	}
	if eventCount == 0 {
		return "", 0, errors.New("aucun écho public à projeter")
	}
	return revision, eventCount, nil
}

func EventsV6(source map[string]any) ([]model.Document, error) {
	events := objectSlice(source["events"])
	if len(events) == 0 {
		return nil, errors.New("aucun écho public à projeter")
	}
	for _, event := range events {
		if err := validatePublicEvent(event); err != nil {
			return nil, err
		}
	}
	sort.SliceStable(events, func(i, j int) bool {
		left, _ := eventTime(events[i])
		right, _ := eventTime(events[j])
		if left.Equal(right) {
			return integer(events[i]["id"]) > integer(events[j]["id"])
		}
		return left.After(right)
	})
	groups := map[string][]map[string]any{}
	for _, event := range events {
		occurred, err := eventTime(event)
		if err != nil {
			return nil, fmt.Errorf("écho sans date valide: %w", err)
		}
		key := occurred.Format("2006-01-02")
		groups[key] = append(groups[key], event)
	}
	dates := make([]string, 0, len(groups))
	for date := range groups {
		dates = append(dates, date)
	}
	sort.Sort(sort.Reverse(sort.StringSlice(dates)))

	var documents []model.Document
	var dayEntries []any
	for _, date := range dates {
		dayEvents := groups[date]
		eventsBytes, err := json.Marshal(dayEvents)
		if err != nil {
			return nil, err
		}
		contentHash := shaHex(eventsBytes)
		generation := "d6-" + strings.ReplaceAll(date, "-", "") + "-" + contentHash[:12]
		cursor := eventCursor(dayEvents)
		facets := eventFacets(dayEvents, true)
		represented := representedEvents(dayEvents)
		confirmed, derived := confidenceCounts(dayEvents)
		lastAt := stringValue(dayEvents[0]["occurredAt"])
		firstAt := stringValue(dayEvents[len(dayEvents)-1]["occurredAt"])
		provenance := map[string]any{"observedAt": lastAt, "sourceUpdatedAt": lastAt, "gameVersion": nil, "steamBuildId": nil, "parserCommit": nil, "catalogCommit": nil, "freshness": "current", "sourceStatus": "available"}
		counts := map[string]any{"echoes": len(dayEvents), "representedEvents": represented, "confirmedEchoes": confirmed, "derivedEchoes": derived}
		fragment := map[string]any{"schemaVersion": 6, "ok": true, "generationId": generation, "date": date, "generatedAt": lastAt, "cursor": cursor, "counts": counts, "facets": facets, "contentHash": "sha256:" + contentHash, "events": dayEvents}
		merge(fragment, provenance)
		fragmentBytes, err := json.Marshal(fragment)
		if err != nil {
			return nil, err
		}
		daily := map[string]any{"schemaVersion": 6, "ok": true, "generationId": generation, "date": date, "generatedAt": lastAt, "cursor": cursor, "counts": counts, "digest": dailyDigest(dayEvents), "latest": firstEvents(dayEvents, eventHeadLimit)}
		merge(daily, provenance)
		dailyBytes, err := json.Marshal(daily)
		if err != nil {
			return nil, err
		}
		fragmentPath := fmt.Sprintf("data/public-events-v6/%s/%s.json", generation, date)
		dailyPath := fmt.Sprintf("data/public-daily/%s/%s.json", generation, date)
		documents = append(documents,
			model.Document{Path: fragmentPath, Content: fragmentBytes, CachePolicy: model.CacheImmutable, GenerationID: generation},
			model.Document{Path: dailyPath, Content: dailyBytes, CachePolicy: model.CacheImmutable, GenerationID: generation},
		)
		dayEntries = append(dayEntries, map[string]any{
			"date": date, "path": fragmentPath, "sha256": "sha256:" + shaHex(fragmentBytes), "fragmentGenerationId": generation,
			"dailyPath": dailyPath, "dailySha256": "sha256:" + shaHex(dailyBytes), "dailyGenerationId": generation,
			"contentHash": "sha256:" + contentHash, "facets": facets, "events": len(dayEvents), "representedEvents": represented,
			"firstAt": firstAt, "lastAt": lastAt,
		})
	}

	revision := stringValue(source["revision"])
	if revision == "" {
		revision = shaHex(mustJSON(events))
	}
	generationHash := sha256.Sum256([]byte(revision))
	generation := "g6-" + hex.EncodeToString(generationHash[:6])
	provenance := sourceProvenance(source)
	generatedAt := stringValue(provenance["sourceUpdatedAt"])
	if generatedAt == "" {
		generatedAt = time.Now().UTC().Format(time.RFC3339Nano)
	}
	cursor := eventCursor(events)
	headEvents := firstEvents(events, eventHeadLimit)
	verified := make([]any, 0, eventHeadLimit)
	for _, event := range events {
		if stringValue(event["confidence"]) == "confirmed" && len(verified) < eventHeadLimit {
			verified = append(verified, event)
		}
	}
	headRevision := "6:" + revision + ":" + fmt.Sprint(cursor["maxId"]) + ":head"
	head := map[string]any{
		"schemaVersion": 6, "ok": true, "baseGenerationId": generation, "revision": headRevision, "generatedAt": generatedAt,
		"cursor": cursor, "windowCursor": eventCursorMap(headEvents),
		"counts":  map[string]any{"echoes": len(headEvents), "verifiedEchoes": len(verified), "totalEchoes": len(events), "representedEvents": representedEventsMap(headEvents)},
		"hasMore": len(events) > len(headEvents), "events": headEvents, "verifiedEchoes": verified,
	}
	merge(head, provenance)
	headBytes, err := json.Marshal(head)
	if err != nil {
		return nil, err
	}
	headPath := fmt.Sprintf("data/public-events-v6/%s/head.json", generation)
	summary := object(source["summary"])
	manifestCounts := map[string]any{
		"rawEvents": metric(summary, "rawEvents", len(events)), "publicEvents": metric(summary, "publicEvents", len(events)),
		"echoes": len(events), "representedEvents": metric(summary, "representedEvents", representedEvents(events)), "days": len(dates),
	}
	manifest := map[string]any{
		"schemaVersion": 6, "ok": true, "generationId": generation, "generatedAt": generatedAt, "sourceRevision": revision,
		"cursor": cursor, "counts": manifestCounts, "facets": eventFacets(events, false),
		"head": map[string]any{"path": headPath, "sha256": "sha256:" + shaHex(headBytes), "revision": headRevision}, "days": dayEntries,
	}
	merge(manifest, provenance)
	manifestBytes, err := json.Marshal(manifest)
	if err != nil {
		return nil, err
	}
	manifestPath := fmt.Sprintf("data/public-events-v6/%s/manifest.json", generation)
	pointer := map[string]any{
		"schemaVersion": 6, "ok": true, "baseGenerationId": generation, "revision": headRevision, "generatedAt": generatedAt,
		"sourceUpdatedAt": provenance["sourceUpdatedAt"], "cursor": cursor, "counts": map[string]any{"totalEchoes": len(events)},
		"manifest": map[string]any{"path": manifestPath, "sha256": "sha256:" + shaHex(manifestBytes)},
		"head":     map[string]any{"path": headPath, "sha256": "sha256:" + shaHex(headBytes), "revision": headRevision},
	}
	pointerBytes, _ := json.Marshal(pointer)
	channelBytes := []byte(`{"schemaVersion":1,"activeContract":"v6","candidateContract":"v6"}`)
	documents = append(documents,
		model.Document{Path: headPath, Content: headBytes, CachePolicy: model.CacheImmutable, GenerationID: generation},
		model.Document{Path: manifestPath, Content: manifestBytes, CachePolicy: model.CacheImmutable, GenerationID: generation},
		model.Document{Path: "data/public-events-manifest-v6.json", Content: manifestBytes, CachePolicy: model.CacheRevalidate, GenerationID: generation},
		model.Document{Path: "data/public-events-head-v6.json", Content: pointerBytes, CachePolicy: model.CacheRevalidate, GenerationID: generation},
		model.Document{Path: "public-events-channel.json", Content: channelBytes, CachePolicy: model.CacheRevalidate, GenerationID: generation},
	)
	return documents, nil
}

func sourceProvenance(source map[string]any) map[string]any {
	raw := object(source["provenance"])
	sourceUpdated := raw["sourceUpdatedAt"]
	if sourceUpdated == nil {
		sourceUpdated = source["updatedAt"]
	}
	observed := raw["observedAt"]
	if observed == nil {
		observed = sourceUpdated
	}
	return map[string]any{
		"observedAt": observed, "sourceUpdatedAt": sourceUpdated, "gameVersion": raw["gameVersion"], "steamBuildId": raw["steamBuildId"],
		"parserCommit": raw["parserCommit"], "catalogCommit": raw["catalogCommit"], "freshness": defaultString(raw["freshness"], "current"),
		"sourceStatus": defaultString(raw["sourceStatus"], "available"),
	}
}

func dailyDigest(events []map[string]any) map[string]any {
	metricNames := []string{"craft", "production", "build", "repair", "capture", "collection", "fishing", "levelUps", "boss", "discovery", "progress", "challenge", "quest", "loot", "note", "mutation", "death", "recovery", "adventure", "rare"}
	totals := map[string]any{"eventCount": len(events), "activePlayers": 0, "onlineSeconds": 0, "presenceSessions": 0}
	for _, name := range metricNames {
		totals[name] = 0
	}
	hourly := make([]any, 24)
	for hour := range 24 {
		hourly[hour] = map[string]any{"hour": hour, "count": 0}
	}
	types := map[string]int{}
	players := map[string]map[string]any{}
	for _, event := range events {
		typeName := defaultString(event["type"], "server")
		types[typeName]++
		occurred, _ := eventTime(event)
		hourRow := hourly[occurred.Hour()].(map[string]any)
		hourRow["count"] = integer(hourRow["count"]) + 1
		playerName := defaultString(event["player"], "Monde")
		player := players[playerName]
		if player == nil {
			metrics := map[string]any{}
			for _, name := range metricNames {
				metrics[name] = 0
			}
			player = map[string]any{"name": playerName, "eventCount": 0, "firstAt": event["occurredAt"], "lastAt": event["occurredAt"], "metrics": metrics, "typeCounts": map[string]any{}, "craftedItems": []any{}, "producedItems": []any{}, "palFinds": []any{}, "highlights": []any{}}
			players[playerName] = player
		}
		player["eventCount"] = integer(player["eventCount"]) + 1
		typeCounts := player["typeCounts"].(map[string]any)
		typeCounts[typeName] = integer(typeCounts[typeName]) + 1
		if stringValue(event["occurredAt"]) < stringValue(player["firstAt"]) {
			player["firstAt"] = event["occurredAt"]
		}
		if stringValue(event["occurredAt"]) > stringValue(player["lastAt"]) {
			player["lastAt"] = event["occurredAt"]
		}
		metricName := typeName
		if typeName == "level" {
			metricName = "levelUps"
		} else if typeName == "research" || typeName == "camp" {
			metricName = "progress"
		}
		if contains(metricNames, metricName) {
			totals[metricName] = integer(totals[metricName]) + 1
			player["metrics"].(map[string]any)[metricName] = integer(player["metrics"].(map[string]any)[metricName]) + 1
		}
		if contains([]string{"level", "boss", "mutation", "research", "quest", "challenge", "note", "camp"}, typeName) {
			totals["rare"] = integer(totals["rare"]) + 1
			player["metrics"].(map[string]any)["rare"] = integer(player["metrics"].(map[string]any)["rare"]) + 1
		}
	}
	playerRows := make([]any, 0, len(players))
	for name, player := range players {
		if name != "Monde" {
			playerRows = append(playerRows, player)
		}
	}
	sort.Slice(playerRows, func(i, j int) bool {
		return integer(playerRows[i].(map[string]any)["eventCount"]) > integer(playerRows[j].(map[string]any)["eventCount"])
	})
	totals["activePlayers"] = len(playerRows)
	return map[string]any{"totals": totals, "hourly": hourly, "types": types, "players": playerRows, "craftedItems": []any{}, "producedItems": []any{}, "palFinds": []any{}, "highlights": []any{}}
}

func eventFacets(events []map[string]any, day bool) map[string]any {
	result := map[string]any{"types": facetRows(events, "type"), "players": facetRows(events, "player")}
	if day {
		result["guilds"] = facetRows(events, "guild")
		result["bases"] = facetRows(events, "base")
	}
	return result
}

func facetRows(events []map[string]any, field string) []any {
	counts := map[string]int{}
	for _, event := range events {
		value := strings.TrimSpace(stringValue(event[field]))
		if value != "" {
			counts[value]++
		}
		if field == "type" {
			details := object(event["details"])
			for _, extra := range stringSlice(details["types"]) {
				if extra != value {
					counts[extra]++
				}
			}
			for _, category := range objectSlice(details["categories"]) {
				extra := strings.TrimSpace(stringValue(category["type"]))
				if extra != "" && extra != value {
					counts[extra]++
				}
			}
		}
	}
	keys := make([]string, 0, len(counts))
	for key := range counts {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	rows := make([]any, 0, len(keys))
	for _, key := range keys {
		rows = append(rows, map[string]any{"value": key, "count": counts[key]})
	}
	return rows
}

func representedEvents(events []map[string]any) int64 {
	var total int64
	for _, event := range events {
		count := integer(object(event["details"])["aggregatedEvents"])
		if count < 1 {
			count = 1
		}
		total += count
	}
	return total
}

func representedEventsMap(events []any) int64 {
	converted := make([]map[string]any, 0, len(events))
	for _, event := range events {
		converted = append(converted, event.(map[string]any))
	}
	return representedEvents(converted)
}

func confidenceCounts(events []map[string]any) (int, int) {
	derived := 0
	for _, event := range events {
		if stringValue(event["confidence"]) == "derived" {
			derived++
		}
	}
	return len(events) - derived, derived
}

func eventCursor(events []map[string]any) map[string]any {
	var minID, maxID int64
	for _, event := range events {
		id := integer(event["id"])
		if id > 0 && (minID == 0 || id < minID) {
			minID = id
		}
		if id > maxID {
			maxID = id
		}
	}
	return map[string]any{"minId": minID, "maxId": maxID}
}

func eventCursorMap(events []any) map[string]any {
	converted := make([]map[string]any, 0, len(events))
	for _, event := range events {
		converted = append(converted, event.(map[string]any))
	}
	return eventCursor(converted)
}

func firstEvents(events []map[string]any, limit int) []any {
	if len(events) < limit {
		limit = len(events)
	}
	result := make([]any, limit)
	for index := 0; index < limit; index++ {
		result[index] = events[index]
	}
	return result
}

func eventTime(event map[string]any) (time.Time, error) {
	return time.Parse(time.RFC3339Nano, stringValue(event["occurredAt"]))
}

func validatePublicEvent(event map[string]any) error {
	if stringValue(event["key"]) == "" || stringValue(event["occurredAt"]) == "" {
		return errors.New("écho public incomplet")
	}
	if err := inspectEventValue(event); err != nil {
		return fmt.Errorf("écho %s refusé: %w", stringValue(event["key"]), err)
	}
	encoded, _ := json.Marshal(event)
	if ipv4Literal.Match(encoded) || strings.Contains(string(encoded), "/srv/") || strings.Contains(strings.ToLower(string(encoded)), "http://") || strings.Contains(strings.ToLower(string(encoded)), "https://") {
		return errors.New("donnée privée détectée dans un écho")
	}
	return nil
}

func inspectEventValue(value any) error {
	switch typed := value.(type) {
	case map[string]any:
		for key, child := range typed {
			if privateEventKey.MatchString(key) {
				return fmt.Errorf("champ privé %s", key)
			}
			if err := inspectEventValue(child); err != nil {
				return err
			}
		}
	case []any:
		for _, child := range typed {
			if err := inspectEventValue(child); err != nil {
				return err
			}
		}
	}
	return nil
}

func metric(summary map[string]any, name string, fallback any) any {
	if value, ok := summary[name]; ok && value != nil {
		return value
	}
	return fallback
}

func merge(target, source map[string]any) {
	for key, value := range source {
		target[key] = value
	}
}

func shaHex(content []byte) string {
	digest := sha256.Sum256(content)
	return hex.EncodeToString(digest[:])
}

func mustJSON(value any) []byte {
	content, _ := json.Marshal(value)
	return content
}

func defaultString(value any, fallback string) string {
	if text := strings.TrimSpace(stringValue(value)); text != "" {
		return text
	}
	return fallback
}

func contains(values []string, expected string) bool {
	for _, value := range values {
		if value == expected {
			return true
		}
	}
	return false
}

func stringSlice(value any) []string {
	var result []string
	items, ok := value.([]any)
	if !ok {
		return result
	}
	for _, item := range items {
		text := strings.TrimSpace(stringValue(item))
		if text != "" {
			result = append(result, text)
		}
	}
	return result
}
