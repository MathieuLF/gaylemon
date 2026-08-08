package projection

import (
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"strings"
)

var publicSettingsFields = map[string]bool{
	"Difficulty": true, "DayTimeSpeedRate": true, "NightTimeSpeedRate": true, "ExpRate": true,
	"PalCaptureRate": true, "PalSpawnNumRate": true, "PalDamageRateAttack": true, "PalDamageRateDefense": true,
	"PlayerDamageRateAttack": true, "PlayerDamageRateDefense": true, "CollectionDropRate": true,
	"CollectionObjectHpRate": true, "CollectionObjectRespawnSpeedRate": true, "EnemyDropItemRate": true,
	"DeathPenalty": true, "BaseCampMaxNum": true, "BaseCampWorkerMaxNum": true, "GuildPlayerMaxNum": true,
	"PalEggDefaultHatchingTime": true, "WorkSpeedRate": true, "AutoSaveSpan": true, "bIsPvP": true,
	"bEnablePlayerToPlayerDamage": true, "bEnableFriendlyFire": true, "bEnableInvaderEnemy": true,
	"bEnableFastTravel": true, "bUseBackupSaveData": true, "CrossplayPlatforms": true,
}

func DecodeObject(content []byte) (map[string]any, error) {
	var value map[string]any
	if err := json.Unmarshal(content, &value); err != nil {
		return nil, err
	}
	return value, nil
}

func PublicMetrics(metrics, stats map[string]any) map[string]any {
	info := object(metrics["info"])
	provenance := object(stats["provenance"])
	statsPlayers := objectSlice(stats["players"])
	lookup := playerLookup(statsPlayers)
	players := make([]any, 0)
	for _, rawPlayer := range objectSlice(metrics["players"]) {
		name := publicName(rawPlayer)
		if name == "" {
			continue
		}
		statsPlayer := findPlayer(rawPlayer, lookup)
		var started, lastOnline any
		if boolean(statsPlayer["isOnline"]) {
			started = statsPlayer["currentSessionStartedAt"]
		}
		lastOnline = statsPlayer["lastOnlineAt"]
		players = append(players, map[string]any{"name": name, "currentSessionStartedAt": started, "onlineSinceAt": started, "lastOnlineAt": lastOnline})
	}
	ok := boolean(metrics["ok"])
	result := map[string]any{
		"version": 2, "schemaVersion": 2, "ok": ok,
		"updatedAt": metrics["updatedAt"], "updatedAtLocal": metrics["updatedAtLocal"],
		"provenance": map[string]any{
			"observedAt": metrics["updatedAt"], "sourceUpdatedAt": metrics["updatedAt"], "gameVersion": info["version"],
			"steamBuildId": provenance["steamBuildId"], "parserCommit": provenance["parserCommit"], "catalogCommit": provenance["catalogCommit"],
			"schemaVersion": 2, "freshness": "current", "sourceStatus": choose(ok, "available", "transient-error"),
		},
		"server":  map[string]any{"name": info["serverName"], "description": info["description"], "version": info["version"]},
		"metrics": metrics["metrics"], "players": players,
	}
	if !ok {
		result["error"] = "Les métriques du serveur sont temporairement indisponibles."
	}
	return result
}

// PublicUptime décrit le dernier contrôle direct de l'API Palworld. La durée
// historique reste conservée dans les exécutions PostgreSQL; ce document sert
// au statut immédiat affiché par le portail.
func PublicUptime(metrics map[string]any) map[string]any {
	ok := boolean(metrics["ok"])
	status := "down"
	statusCode := 0
	message := "API REST Palworld indisponible"
	if ok {
		status = "up"
		statusCode = 1
		message = "Palworld OK"
	}
	updatedAt := metrics["updatedAt"]
	values := object(metrics["metrics"])
	beat := map[string]any{
		"status": status, "statusCode": statusCode, "time": updatedAt, "ping": nil, "message": message,
	}
	monitor := map[string]any{
		"id": "palworld-rest-api", "name": "Serveur Palworld", "type": "rest-api", "status": status,
		"statusCode": statusCode, "lastHeartbeatAt": updatedAt, "lastProbeAt": updatedAt, "ping": nil,
		"uptime24h": chooseNumber(ok, 100, 0), "uptimeSeconds": values["uptimeSeconds"], "uptime": values["uptime"],
		"beats": []any{beat},
	}
	return map[string]any{
		"version": 2, "ok": true, "source": "palworld-rest-api", "updatedAt": updatedAt,
		"updatedAtLocal": metrics["updatedAtLocal"], "title": "Palworld", "monitors": []any{monitor},
		"summary": map[string]any{
			"total": 1, "up": statusCode, "down": 1 - statusCode, "maintenance": 0, "status": status, "monitorStatus": status,
			"probeFresh": true, "probeAgeSeconds": 0, "heartbeatAgeSeconds": 0, "uptime24hAverage": chooseNumber(ok, 100, 0),
			"uptimeLast24h": chooseNumber(ok, 100, 0), "unavailableSecondsLast24h": 0, "averagePing": nil,
			"players": values["players"], "maxPlayers": values["maxPlayers"], "fps": values["fps"],
			"fpsAverage": values["fpsAverage"], "frameMs": values["frameMs"], "gameUptimeSeconds": values["uptimeSeconds"],
		},
	}
}

func PublicStats(stats map[string]any) map[string]any {
	provenance := object(stats["provenance"])
	collection := object(stats["collection"])
	settings := object(stats["settings"])
	publicSources := map[string]any{}
	for _, name := range []string{"info", "metrics", "players", "settings", "game-data"} {
		source := object(object(stats["sources"])[name])
		if len(source) == 0 {
			continue
		}
		status := source["status"]
		if name == "game-data" && collection["gameDataStatus"] != nil {
			status = collection["gameDataStatus"]
		}
		publicSources[name] = map[string]any{
			"status": status, "lastObservedAt": source["lastObservedAt"], "lastSuccessAt": source["lastSuccessAt"],
			"latencyMs": source["latencyMs"], "latencyP95Ms": source["latencyP95Ms"], "responseBytes": source["responseBytes"],
			"consecutiveFailures": source["consecutiveFailures"],
		}
	}
	guilds := make([]any, 0)
	for _, guild := range objectSlice(stats["guilds"]) {
		name := stringValue(guild["name"])
		if name == "" {
			name = "Guilde"
		}
		guilds = append(guilds, map[string]any{"name": name, "baseCount": integer(guild["baseCount"]), "playerCount": integer(guild["playerCount"]), "activePlayerCount": integer(guild["activePlayerCount"])})
	}
	players := make([]any, 0)
	for _, player := range objectSlice(stats["players"]) {
		if public := publicPlayer(player); public != nil {
			players = append(players, public)
		}
	}
	ok := boolean(stats["ok"])
	result := map[string]any{
		"version": 2, "schemaVersion": 2, "ok": ok, "updatedAt": stats["updatedAt"], "updatedAtLocal": stats["updatedAtLocal"],
		"provenance": map[string]any{
			"observedAt": provenance["observedAt"], "sourceUpdatedAt": provenance["sourceUpdatedAt"], "gameVersion": provenance["gameVersion"],
			"steamBuildId": provenance["steamBuildId"], "parserCommit": provenance["parserCommit"], "catalogCommit": provenance["catalogCommit"],
			"schemaVersion": 2, "freshness": provenance["freshness"], "sourceStatus": provenance["sourceStatus"],
		},
		"collection": map[string]any{
			"source": collection["source"], "firstSampleAt": collection["firstSampleAt"], "lastSampleAt": collection["lastSampleAt"],
			"sampleCount": collection["sampleCount"], "gameDataAvailable": boolean(collection["gameDataAvailable"]), "gameDataStatus": collection["gameDataStatus"],
			"lastGameDataAt": collection["lastGameDataAt"], "nextGameDataAttemptAt": collection["nextGameDataAttemptAt"],
			"settingsStatus": settings["status"], "lastSettingsAt": settings["updatedAt"], "note": nil,
		},
		"settings": map[string]any{"status": settings["status"], "updatedAt": settings["updatedAt"], "current": publicSettings(object(settings["current"]))},
		"sources":  publicSources, "server": stats["server"], "actors": stats["actors"], "guilds": guilds, "players": players,
	}
	if !ok {
		result["error"] = "Les statistiques du serveur sont temporairement indisponibles."
	}
	return result
}

func publicPlayer(player map[string]any) map[string]any {
	name := publicName(player)
	if name == "" {
		return nil
	}
	online := boolean(player["isOnline"])
	var started any
	if online {
		started = player["currentSessionStartedAt"]
	}
	history := make([]any, 0)
	allHistory := objectSlice(player["sessionHistory"])
	if len(allHistory) > 40 {
		allHistory = allHistory[len(allHistory)-40:]
	}
	for _, session := range allHistory {
		if stringValue(session["startedAt"]) != "" {
			history = append(history, map[string]any{"startedAt": session["startedAt"], "endedAt": session["endedAt"]})
		}
	}
	var totalOnline any
	if stringValue(player["totalOnline"]) != "" {
		totalOnline = fmt.Sprint(player["totalOnline"])
	}
	return map[string]any{
		"name": name, "isOnline": online, "sessionCount": integer(player["sessionCount"]), "currentSessionStartedAt": started,
		"onlineSinceAt": started, "lastSessionEndedAt": player["lastSessionEndedAt"], "sessionHistory": history,
		"totalOnlineSeconds": integer(player["totalOnlineSeconds"]), "totalOnline": totalOnline, "level": player["level"],
		"buildingCount": player["buildingCount"], "ping": player["ping"], "position": publicPosition(object(player["location"])),
		"guildName": player["guildName"], "activePalCount": integer(player["activePalCount"]), "basePalCount": integer(player["basePalCount"]),
		"lastSeenAt": player["lastSeenAt"], "lastOnlineAt": player["lastOnlineAt"],
	}
}

func publicPosition(location map[string]any) any {
	if len(location) == 0 || (location["x"] == nil && location["y"] == nil) {
		return nil
	}
	var x, y any
	if location["x"] != nil {
		x = math.Round(number(location["x"])/1000) * 1000
	}
	if location["y"] != nil {
		y = math.Round(number(location["y"])/1000) * 1000
	}
	return map[string]any{"x": x, "y": y, "label": "X " + coordinate(x) + " / Y " + coordinate(y), "precision": "approximate"}
}

func coordinate(value any) string {
	if value == nil {
		return "--"
	}
	n := number(value)
	if math.Abs(n) >= 1000 {
		return fmt.Sprintf("%.0fk", n/1000)
	}
	return fmt.Sprintf("%.0f", n)
}

func publicSettings(settings map[string]any) map[string]any {
	keys := make([]string, 0, len(publicSettingsFields))
	for key := range publicSettingsFields {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	result := map[string]any{}
	for _, key := range keys {
		if value, ok := settings[key]; ok && value != nil {
			result[key] = value
		}
	}
	return result
}

func publicName(player map[string]any) string {
	name := strings.TrimSpace(stringValue(player["name"]))
	switch strings.ToLower(name) {
	case "", "joueur", "player", "unknown", "inconnu", "joueur inconnu":
		return ""
	default:
		return name
	}
}

func playerLookup(players []map[string]any) map[string]map[string]any {
	lookup := map[string]map[string]any{}
	for _, player := range players {
		for _, field := range []string{"name", "accountName", "playerId", "userId", "id"} {
			key := strings.ToLower(strings.TrimSpace(stringValue(player[field])))
			if key != "" {
				if _, exists := lookup[key]; !exists {
					lookup[key] = player
				}
			}
		}
	}
	return lookup
}

func findPlayer(player map[string]any, lookup map[string]map[string]any) map[string]any {
	for _, field := range []string{"name", "accountName", "playerId", "userId", "id"} {
		key := strings.ToLower(strings.TrimSpace(stringValue(player[field])))
		if match := lookup[key]; key != "" && match != nil {
			return match
		}
	}
	return map[string]any{}
}

func object(value any) map[string]any {
	if typed, ok := value.(map[string]any); ok {
		return typed
	}
	return map[string]any{}
}

func objectSlice(value any) []map[string]any {
	var result []map[string]any
	switch typed := value.(type) {
	case []any:
		for _, item := range typed {
			if objectValue, ok := item.(map[string]any); ok {
				result = append(result, objectValue)
			}
		}
	case map[string]any:
		keys := make([]string, 0, len(typed))
		for key := range typed {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			if objectValue, ok := typed[key].(map[string]any); ok {
				result = append(result, objectValue)
			}
		}
	}
	return result
}

func stringValue(value any) string {
	if value == nil {
		return ""
	}
	if typed, ok := value.(string); ok {
		return typed
	}
	return fmt.Sprint(value)
}

func boolean(value any) bool {
	switch typed := value.(type) {
	case bool:
		return typed
	case string:
		return strings.EqualFold(typed, "true")
	case float64:
		return typed != 0
	default:
		return false
	}
}

func number(value any) float64 {
	switch typed := value.(type) {
	case float64:
		return typed
	case int:
		return float64(typed)
	case int64:
		return float64(typed)
	case json.Number:
		result, _ := typed.Float64()
		return result
	default:
		return 0
	}
}

func integer(value any) int64 { return int64(number(value)) }

func choose(condition bool, yes, no string) string {
	if condition {
		return yes
	}
	return no
}

func chooseNumber(condition bool, yes, no float64) float64 {
	if condition {
		return yes
	}
	return no
}
