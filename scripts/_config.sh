#!/bin/bash
# Shared config loader — source this from any script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/_config.sh"
# Provides: IMAGE_NAME, IMAGE_TAG, CONTAINER_NAME, VOLUME_NAME, ACTIVE_PROFILE,
#           VOLUME_MOUNT_ARGS, PORT_MAPPING_ARGS

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
# Use read with IFS='' to get the raw line, then split on first '=' only
while IFS= read -r _line || [[ -n "$_line" ]]; do
    _line="${_line#"${_line%%[![:space:]]*}"}"   # ltrim
    _line="${_line%"${_line##*[![:space:]]}"}"   # rtrim
    [[ -z "$_line" || "$_line" == \#* ]] && continue
    _key="${_line%%=*}"
    _val="${_line#*=}"
    export "${_key}=${_val}"
done < "$_CONF_FILE"

# Parse VOLUME_MOUNTS into an array (semicolon-separated host_path:container_path)
# Example in .conf:  VOLUME_MOUNTS=/host/data:/data;/host/projects:/workspace
VOLUME_MOUNT_ARGS=()
if [[ -n "$VOLUME_MOUNTS" ]]; then
    IFS=';' read -ra _mounts <<< "$VOLUME_MOUNTS"
    for _mount in "${_mounts[@]}"; do
        _mount="$(echo "$_mount" | xargs)"
        [[ -z "$_mount" ]] && continue
        VOLUME_MOUNT_ARGS+=(-v "$_mount")
    done
fi

# Parse PORT_MAPPINGS into an array (semicolon-separated host:container[/tcp|udp])
# Example in .conf:  PORT_MAPPINGS=3000:3000;5353:53/udp
PORT_MAPPING_ARGS=()
if [[ -n "$PORT_MAPPINGS" ]]; then
    IFS=';' read -ra _ports <<< "$PORT_MAPPINGS"
    for _port in "${_ports[@]}"; do
        _port="$(echo "$_port" | xargs)"
        [[ -z "$_port" ]] && continue
        PORT_MAPPING_ARGS+=(-p "$_port")
    done
fi

