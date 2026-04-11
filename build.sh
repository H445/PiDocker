#!/bin/bash
# Build the pi-agent Docker image and start the container

set -uo pipefail

IMAGE_NAME="pi-agent"
IMAGE_TAG="latest"
CONTAINER_NAME="pi-agent"
VOLUME_NAME="pi-agent-data"

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

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container exists. Starting..."
    docker start "${CONTAINER_NAME}"
else
    echo "Creating new container and volume..."
    # Create volume if it doesn't exist
    docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1 || docker volume create "${VOLUME_NAME}"
    # Create and start container
    docker run -d \
        --name "${CONTAINER_NAME}" \
        -v "${VOLUME_NAME}":/root \
        "${IMAGE_NAME}:${IMAGE_TAG}"
fi

if [ $? -eq 0 ]; then
    echo "✓ Container started successfully"
    echo
    echo "Next steps:"
    echo "  1. Configure local providers (optional): ./run.sh → [5]"
    echo "  2. Launch pi: ./run.sh → [1]"
else
    echo "✗ Failed to start container"
    exit 1
fi
