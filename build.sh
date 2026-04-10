#!/bin/bash
# Build the pi-agent Docker image

IMAGE_NAME="pi-agent"
IMAGE_TAG="latest"

echo "Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

if [ $? -eq 0 ]; then
    echo "✓ Image built successfully: ${IMAGE_NAME}:${IMAGE_TAG}"
else
    echo "✗ Build failed"
    exit 1
fi
