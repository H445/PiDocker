#!/bin/bash
# Build the pi-agent Docker image and start the container

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_config.sh"

echo "Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

if [ $? -eq 0 ]; then
    echo "✓ Image built successfully: ${IMAGE_NAME}:${IMAGE_TAG}"
else
    echo "✗ Build failed"
    exit 1
fi

echo
echo "Starting container: ${CONTAINER_NAME}"

# Check if container already exists — remove so we can recreate with the new image
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Removing old container..."
    docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

echo "Creating new container and volume..."
# Create volume if it doesn't exist
docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1 || docker volume create "${VOLUME_NAME}"
# Create and start container with a keep-alive command
docker run -d \
    --name "${CONTAINER_NAME}" \
    -v "${VOLUME_NAME}":/root \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "${IMAGE_NAME}:${IMAGE_TAG}" \
    tail -f /dev/null

if [ $? -eq 0 ]; then
    echo "✓ Container started successfully"
    echo
    echo "Next steps:"
    echo "  1. Configure local providers (optional): ./run.sh → [4]"
    echo "  2. Launch pi: ./run.sh → [1]"
else
    echo "✗ Failed to start container"
    exit 1
fi
