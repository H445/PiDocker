#!/bin/bash
# Launch the pi-agent Docker container persistently

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_config.sh"

IMAGE_FULL="${IMAGE_NAME}:${IMAGE_TAG}"

# Check if container already exists
if docker ps -a --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
    # Try to start the existing container
    docker start "${CONTAINER_NAME}" >/dev/null 2>&1 || true

    # Verify it's actually running
    state="$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null || true)"
    if [[ "$state" != "true" ]]; then
        echo "Container '${CONTAINER_NAME}' won't stay running. Recreating..."
        docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1
        docker run -d \
            --name "${CONTAINER_NAME}" \
            -v "${VOLUME_NAME}:/root" \
            -v /var/run/docker.sock:/var/run/docker.sock \
            "${IMAGE_FULL}" \
            tail -f /dev/null
    else
        echo "Container '${CONTAINER_NAME}' is running."
    fi
else
    echo "Creating new persistent container: ${CONTAINER_NAME}"
    docker run -d \
        --name "${CONTAINER_NAME}" \
        -v "${VOLUME_NAME}:/root" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "${IMAGE_FULL}" \
        tail -f /dev/null
fi

# Execute interactive pi session
echo "Launching pi in container..."
docker exec -it "${CONTAINER_NAME}" pi
