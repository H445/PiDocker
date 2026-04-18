#!/bin/bash
# Launch the pi-agent Docker container persistently

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_config.sh"

IMAGE_FULL="${IMAGE_NAME}:${IMAGE_TAG}"

# ── helper: check if container's mounts match what the profile requires ────────
container_mounts_match() {
    local container="$1"
    # Use .Name for named volumes, .Source for bind mounts — avoids comparing
    # raw host paths like /var/lib/docker/volumes/... against the volume name
    local actual_mounts
    actual_mounts="$(docker inspect --format \
        '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{else}}{{.Source}}{{end}}:{{.Destination}} {{end}}' \
        "$container" 2>/dev/null)"

    # Named volume
    if [[ "$actual_mounts" != *"${VOLUME_NAME}:/root"* ]]; then
        return 1
    fi

    # Extra VOLUME_MOUNTS from profile
    for mount_spec in "${VOLUME_MOUNT_ARGS[@]}"; do
        # VOLUME_MOUNT_ARGS entries are: "-v" "host:ctn" alternating
        # Skip the "-v" entries, check the path entries
        [[ "$mount_spec" == "-v" ]] && continue
        if [[ "$actual_mounts" != *"${mount_spec}"* ]]; then
            return 1
        fi
    done
    return 0
}

# ── helper: create the container with all configured mounts ───────────────────
docker_run() {
    docker run -d \
        --name "${CONTAINER_NAME}" \
        -v "${VOLUME_NAME}:/root" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "${VOLUME_MOUNT_ARGS[@]}" \
        "${IMAGE_FULL}" \
        tail -f /dev/null
}

# ── main ──────────────────────────────────────────────────────────────────────
if docker ps -a --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
    # Container exists — check if mounts match before deciding to reuse it
    if ! container_mounts_match "${CONTAINER_NAME}"; then
        echo "Container '${CONTAINER_NAME}' mount config has changed. Recreating..."
        docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1
        docker_run
    else
        # Mounts are correct — just make sure it's running
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
