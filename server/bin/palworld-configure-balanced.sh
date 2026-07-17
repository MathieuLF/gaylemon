#!/usr/bin/env bash
set -euo pipefail

GAME_DIR="/srv/storage/steam/servers/palworld/game"
PALWORLD_DIR="/srv/storage/steam/servers/palworld"
CANONICAL_CFG="$PALWORLD_DIR/config/PalWorldSettings.ini"
TARGET_CFG="$GAME_DIR/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini"

SERVER_PASSWORD="${SERVER_PASSWORD:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
SERVER_NAME="${SERVER_NAME:-Gaylemon Palworld 1.0}"
SERVER_DESCRIPTION="${SERVER_DESCRIPTION:-Serveur prive - challenge PvE raisonnable pour 8-10 joueurs}"

if [ -z "$SERVER_PASSWORD" ] || [ -z "$ADMIN_PASSWORD" ]; then
  echo "SERVER_PASSWORD and ADMIN_PASSWORD must be set." >&2
  exit 1
fi

if [ ! -f "$GAME_DIR/DefaultPalWorldSettings.ini" ]; then
  echo "DefaultPalWorldSettings.ini was not found. Install Palworld first." >&2
  exit 1
fi

install -d -o steam -g steam -m 0755 "$(dirname "$CANONICAL_CFG")" "$(dirname "$TARGET_CFG")"
install -o steam -g steam -m 0640 "$GAME_DIR/DefaultPalWorldSettings.ini" "$CANONICAL_CFG"

set_setting() {
  local key="$1"
  local value="$2"

  KEY="$key" VALUE="$value" perl -0pi -e \
    's/(\b\Q$ENV{KEY}\E=)(?:"[^"]*"|[^,)]*)/$1$ENV{VALUE}/g' \
    "$CANONICAL_CFG"
}

quote_ini() {
  printf '"%s"' "$1"
}

# Challenging private PvE profile for roughly 8-10 players.
set_setting ExpRate 1.000000
set_setting PalCaptureRate 0.950000
set_setting PalSpawnNumRate 1.000000
set_setting PlayerStomachDecreaceRate 1.100000
set_setting PlayerStaminaDecreaceRate 1.050000
set_setting PalStomachDecreaceRate 1.050000
set_setting PalStaminaDecreaceRate 1.000000
set_setting BuildObjectDeteriorationDamageRate 0.400000
set_setting CollectionDropRate 1.100000
set_setting CollectionObjectRespawnSpeedRate 1.000000
set_setting EnemyDropItemRate 1.000000
set_setting DeathPenalty Item
set_setting BaseCampWorkerMaxNum 18
set_setting GuildPlayerMaxNum 12
set_setting BaseCampMaxNumInGuild 5
set_setting PalEggDefaultHatchingTime 0.750000
set_setting WorkSpeedRate 1.000000
set_setting bIsPvP False
set_setting bEnablePlayerToPlayerDamage False
set_setting bEnableFriendlyFire False
set_setting bHardcore False
set_setting bPalLost False
set_setting bEnableNonLoginPenalty False
set_setting bEnableFastTravel True
set_setting bIsStartLocationSelectByMap True
set_setting bBuildAreaLimit True
set_setting ServerPlayerMaxNum 12
set_setting ServerName "$(quote_ini "$SERVER_NAME")"
set_setting ServerDescription "$(quote_ini "$SERVER_DESCRIPTION")"
set_setting AdminPassword "$(quote_ini "$ADMIN_PASSWORD")"
set_setting ServerPassword "$(quote_ini "$SERVER_PASSWORD")"
set_setting bAllowClientMod False
set_setting PublicPort 8211
set_setting RCONEnabled False
set_setting RESTAPIEnabled True
set_setting RESTAPIPort 8212
set_setting bShowPlayerList True
set_setting bIsShowJoinLeftMessage True
set_setting ChatPostLimitPerMinute 20
set_setting bIsUseBackupSaveData True
set_setting LogFormatType Text
set_setting SupplyDropSpan 180
set_setting EnablePredatorBossPal True
set_setting bAllowGlobalPalboxExport False
set_setting bAllowGlobalPalboxImport False
set_setting EquipmentDurabilityDamageRate 1.050000
set_setting MonsterFarmActionSpeedRate 1.000000

install -o steam -g steam -m 0640 "$CANONICAL_CFG" "$TARGET_CFG"
chown -R steam:steam "$PALWORLD_DIR/config" "$GAME_DIR/Pal/Saved"

echo "Palworld challenge configuration written to $TARGET_CFG."
