#!/bin/bash
# Launch the pi-agent Docker container persistently

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_config.sh"

IMAGE_FULL="${IMAGE_NAME}:${IMAGE_TAG}"

# ── helper: check if container's mounts match what the profile requires ────────
container_mounts_match() {
    local container="$1"
    # Docker Desktop rewrites host paths to internal Linux-style paths
    # (e.g. /run/desktop/mnt/host/d/...), so comparing source paths is
    # unreliable.  Compare only destination paths + named-volume name.
    local mount_info
    mount_info="$(docker inspect --format \
        '{{range .Mounts}}{{.Name}}|{{.Destination}} {{end}}' \
        "$container" 2>/dev/null)"

    # Named volume check
    if [[ "$mount_info" != *"${VOLUME_NAME}|/root"* ]]; then
        return 1
    fi

    # Extra bind mounts: check container-side destination paths
    for mount_spec in "${VOLUME_MOUNT_ARGS[@]}"; do
        [[ "$mount_spec" == "-v" ]] && continue
        # mount_spec is "host_path:container_path" — grab container path
        local ctn_path="${mount_spec#*:}"
        if [[ "$mount_info" != *"|${ctn_path} "* ]]; then
            return 1
        fi
    done

    # Verify total mount count to detect stale extra mounts
    # Expected: root volume + docker.sock + each extra mount
    local expected_count=$(( 2 + ${#VOLUME_MOUNT_ARGS[@]} / 2 ))
    local actual_count
    actual_count="$(echo "$mount_info" | grep -o '|' | wc -l)"
    if [[ "$actual_count" -ne "$expected_count" ]]; then
        return 1
    fi

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
