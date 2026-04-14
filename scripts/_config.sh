#!/bin/bash
# Shared config loader — source this from any script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/_config.sh"
# Provides: IMAGE_NAME, IMAGE_TAG, CONTAINER_NAME, VOLUME_NAME, ACTIVE_PROFILE

_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/configs"
_ACTIVE_FILE="$_CONFIG_DIR/.active"

if [[ ! -f "$_ACTIVE_FILE" ]]; then
    echo "No active configuration found. Run ./setup.sh first." >&2
    exit 1
fi

ACTIVE_PROFILE="$(cat "$_ACTIVE_FILE" | tr -d '[:space:]')"
_CONF_FILE="$_CONFIG_DIR/${ACTIVE_PROFILE}.conf"

if [[ ! -f "$_CONF_FILE" ]]; then
    echo "Active profile '$ACTIVE_PROFILE' not found at $_CONF_FILE. Run ./setup.sh to fix." >&2
    exit 1
fi

# Source the key=value file directly
while IFS='=' read -r key value; do
    key="$(echo "$key" | xargs)"
    value="$(echo "$value" | xargs)"
    [[ -z "$key" || "$key" == \#* ]] && continue
    export "$key=$value"
done < "$_CONF_FILE"

