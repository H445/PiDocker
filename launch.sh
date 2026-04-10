#!/bin/bash
# Launch the pi-agent Docker container persistently

set -euo pipefail

CONTAINER_NAME="pi-agent"
IMAGE_NAME="pi-agent:latest"

launch_pi() {
    if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* || "${OSTYPE:-}" == win32* ]] && command -v winpty >/dev/null 2>&1; then
        exec winpty docker exec -it "${CONTAINER_NAME}" pi
    fi

    if [ -t 0 ] && [ -t 1 ]; then
        exec docker exec -it "${CONTAINER_NAME}" pi
    fi

    echo "No interactive TTY detected; attaching without terminal emulation."
    exec docker exec -i "${CONTAINER_NAME}" pi
}

if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    echo "Image '${IMAGE_NAME}' was not found. Build it first with ./build.sh"
    exit 1
fi

# Check if container already exists
if docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
    if [ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}")" = "true" ]; then
        echo "Container '${CONTAINER_NAME}' is already running."
    else
        echo "Container '${CONTAINER_NAME}' already exists. Starting it..."
        docker start "${CONTAINER_NAME}" >/dev/null
    fi
else
    echo "Creating new persistent container: ${CONTAINER_NAME}"
    docker run -d \
        --name "${CONTAINER_NAME}" \
        -v pi-agent-data:/root \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "${IMAGE_NAME}" \
        tail -f /dev/null >/dev/null
fi

# Execute interactive pi session
echo "Launching pi in container..."
launch_pi
