#!/usr/bin/env bash

gaylemon_curl_config_file() {
  local temp_root="${TMPDIR:-/tmp}"
  umask 0077
  mktemp "$temp_root/gaylemon-curl.XXXXXX"
}

gaylemon_curl_escape_config_value() {
  local value="$1"
  case "$value" in
    *$'\r'*|*$'\n'*)
      return 1
      ;;
  esac
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

gaylemon_curl_write_basic() {
  local file="$1"
  local username="$2"
  local password="$3"
  local credentials=""
  credentials="$(gaylemon_curl_escape_config_value "${username}:${password}")" || return 1
  printf 'user = "%s"\n' "$credentials" > "$file"
  chmod 0600 "$file"
}

gaylemon_curl_write_bearer() {
  local file="$1"
  local token="$2"
  local header=""
  header="$(gaylemon_curl_escape_config_value "Authorization: Bearer ${token}")" || return 1
  printf 'header = "%s"\n' "$header" > "$file"
  chmod 0600 "$file"
}
