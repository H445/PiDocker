#!/bin/bash
# Launch the pi-agent Docker container persistently

CONTAINER_NAME="pi-agent"
IMAGE_NAME="pi-agent:latest"

# Check if container already exists
if docker ps -a --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
    echo "Container '${CONTAINER_NAME}' already exists. Starting it..."
    docker start "${CONTAINER_NAME}"
else
    echo "Creating new persistent container: ${CONTAINER_NAME}"
    docker run -d \
        --name "${CONTAINER_NAME}" \
        -v pi-agent-data:/root \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "${IMAGE_NAME}" \
        tail -f /dev/null
fi

# Execute interactive pi session
echo "Launching pi in container..."
docker exec -it "${CONTAINER_NAME}" pi
