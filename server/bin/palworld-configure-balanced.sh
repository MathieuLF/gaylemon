#!/usr/bin/env bash
set -euo pipefail

GAME_DIR="/srv/storage/steam/servers/palworld/game"
PALWORLD_DIR="/srv/storage/steam/servers/palworld"
ENV_FILE="/etc/palworld/palworld.env"
CANONICAL_CFG="$PALWORLD_DIR/config/PalWorldSettings.ini"
TARGET_CFG="$GAME_DIR/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini"

load_env() {
  if [ -r "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
  fi
}

load_env

read_existing_setting() {
  local key="$1"
  local file
  local value

  for file in "$CANONICAL_CFG" "$TARGET_CFG"; do
    [ -f "$file" ] || continue
    value="$(KEY="$key" perl -ne 'if (/\b\Q$ENV{KEY}\E=(?:"([^"]*)"|([^,)]*))/) { print defined($1) ? $1 : $2; exit }' "$file")"
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
  done
}

SERVER_PASSWORD="${SERVER_PASSWORD:-$(read_existing_setting ServerPassword)}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(read_existing_setting AdminPassword)}"
SERVER_NAME="${SERVER_NAME:-$(read_existing_setting ServerName)}"
SERVER_NAME="${SERVER_NAME:-Gaylemon Palworld 1.0}"
SERVER_DESCRIPTION="${SERVER_DESCRIPTION:-$(read_existing_setting ServerDescription)}"
SERVER_DESCRIPTION="${SERVER_DESCRIPTION:-Serveur prive - challenge PvE ferme pour 8-10 joueurs}"

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
    'my $key = $ENV{KEY};
     my $value = $ENV{VALUE};
     my $changed = s/(\b\Q$key\E=)(?:"[^"]*"|[^,)]*)/$1$value/g;
     if (!$changed) {
       s/(OptionSettings=\([^)]*)\)/$1,$key=$value)/s;
     }' \
    "$CANONICAL_CFG"
}

print_setting() {
  local key="$1"
  printf '%s=' "$key"
  KEY="$key" perl -ne 'if (/\b\Q$ENV{KEY}\E=(?:"([^"]*)"|([^,)]*))/) { print defined($1) ? $1 : $2; exit }' "$TARGET_CFG"
  printf '\n'
}

quote_ini() {
  printf '"%s"' "$1"
}

# Challenging private PvE profile for roughly 8-10 players.
set_setting DayTimeSpeedRate 1.000000
set_setting NightTimeSpeedRate 0.700000
set_setting ExpRate 1.000000
set_setting PalCaptureRate 0.800000
set_setting PalSpawnNumRate 1.000000
set_setting PlayerStomachDecreaceRate 1.150000
set_setting PlayerStaminaDecreaceRate 1.100000
set_setting PalStomachDecreaceRate 1.100000
set_setting PalStaminaDecreaceRate 1.050000
set_setting BuildObjectDeteriorationDamageRate 0.400000
set_setting CollectionDropRate 1.000000
set_setting CollectionObjectRespawnSpeedRate 1.000000
set_setting EnemyDropItemRate 1.000000
set_setting DeathPenalty Item
set_setting BaseCampWorkerMaxNum 18
set_setting GuildPlayerMaxNum 12
set_setting BaseCampMaxNumInGuild 5
set_setting PalEggDefaultHatchingTime 2.000000
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
set_setting bAllowGlobalPalboxExport True
set_setting bAllowGlobalPalboxImport True
set_setting EquipmentDurabilityDamageRate 1.100000
set_setting MonsterFarmActionSpeedRate 0.700000

install -o steam -g steam -m 0640 "$CANONICAL_CFG" "$TARGET_CFG"
chown -R steam:steam "$PALWORLD_DIR/config" "$GAME_DIR/Pal/Saved"

echo "Palworld challenge configuration written to $TARGET_CFG."
print_setting NightTimeSpeedRate
print_setting PalCaptureRate
print_setting PlayerStomachDecreaceRate
print_setting PlayerStaminaDecreaceRate
print_setting PalStomachDecreaceRate
print_setting PalStaminaDecreaceRate
print_setting CollectionDropRate
print_setting PalEggDefaultHatchingTime
print_setting bAllowGlobalPalboxExport
print_setting bAllowGlobalPalboxImport
print_setting MonsterFarmActionSpeedRate
print_setting EquipmentDurabilityDamageRate
