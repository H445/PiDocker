#!/bin/bash
# Launch the pi-agent Docker container persistently

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_config.sh"

IMAGE_FULL="${IMAGE_NAME}:${IMAGE_TAG}"

# ── Runtime-config fingerprint ────────────────────────────────────────────────
# Instead of inspecting Docker (which rewrites paths on Docker Desktop),
# save a fingerprint file when creating/recreating the container and compare
# it on the next launch.
if [[ -d "$SCRIPT_DIR/configs" ]]; then
    _CONFIG_DIR="$SCRIPT_DIR/configs"
else
    _CONFIG_DIR="$(dirname "$SCRIPT_DIR")/configs"
fi
_MOUNT_FINGERPRINT_FILE="${_CONFIG_DIR}/.mounts_${CONTAINER_NAME}"

get_mount_fingerprint() {
    echo "volume=${VOLUME_NAME}:/root"
    # Sort the extra mount specs for deterministic comparison
    for mount_spec in "${VOLUME_MOUNT_ARGS[@]}"; do
        [[ "$mount_spec" == "-v" ]] && continue
        echo "bind=$mount_spec"
    done | sort
    for port_spec in "${PORT_MAPPING_ARGS[@]}"; do
        [[ "$port_spec" == "-p" ]] && continue
        echo "port=$port_spec"
    done | sort
}

CURRENT_FINGERPRINT="$(get_mount_fingerprint)"

save_mount_fingerprint() {
    printf '%s' "$CURRENT_FINGERPRINT" > "$_MOUNT_FINGERPRINT_FILE"
}

mount_fingerprint_matches() {
    [[ -f "$_MOUNT_FINGERPRINT_FILE" ]] || return 1
    local saved
    saved="$(cat "$_MOUNT_FINGERPRINT_FILE")"
    [[ "$saved" == "$CURRENT_FINGERPRINT" ]]
}

# ── helper: create the container with all configured mounts ───────────────────
docker_run() {
    docker run -d \
        --name "${CONTAINER_NAME}" \
        -v "${VOLUME_NAME}:/root" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "${VOLUME_MOUNT_ARGS[@]}" \
        "${PORT_MAPPING_ARGS[@]}" \
        "${IMAGE_FULL}" \
        tail -f /dev/null
    # Save fingerprint so next launch knows the config hasn't changed
    save_mount_fingerprint
}

# ── main ──────────────────────────────────────────────────────────────────────
if docker ps -a --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
    # Container exists — compare saved runtime fingerprint to current config
    if ! mount_fingerprint_matches; then
        echo "Container '${CONTAINER_NAME}' runtime config has changed (mounts/ports). Recreating..."
        docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1
        docker_run
    else
        # Runtime config is correct — just make sure it's running
        docker start "${CONTAINER_NAME}" >/dev/null 2>&1 || true

        state="$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null || true)"
        if [[ "$state" != "true" ]]; then
            echo "Container '${CONTAINER_NAME}' won't stay running. Recreating..."
            docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1
            docker_run
        else
            echo "Container '${CONTAINER_NAME}' is running."
        fi
    fi
else
    echo "Creating new persistent container: ${CONTAINER_NAME}"
    docker_run
fi

# Execute interactive pi session
echo "Launching pi in container..."
docker exec -it "${CONTAINER_NAME}" pi
