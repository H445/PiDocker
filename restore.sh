#!/bin/bash
# Restore a pi-agent container from backup

CONTAINER_NAME="pi-agent"
IMAGE_NAME="pi-agent:latest"
BACKUP_DIR="backups"

# Show available backups if no argument provided
if [ -z "$1" ]; then
    echo "Available backups:"
    if [ ! -d "${BACKUP_DIR}" ] || [ -z "$(ls -1 ${BACKUP_DIR}/*.tar.gz 2>/dev/null)" ]; then
        echo "  No backups found in ${BACKUP_DIR}/"
        exit 1
    fi
    
    ls -lh "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | awk '{print $NF}' | nl
    echo ""
    echo "Usage: ./restore.sh <backup_file>"
    echo "Example: ./restore.sh backups/pi-agent-backup-20250101_120000.tar.gz"
    exit 0
fi

BACKUP_FILE="$1"

# Validate backup file exists
if [ ! -f "${BACKUP_FILE}" ]; then
    echo "✗ Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

echo "Restoring from backup: ${BACKUP_FILE}"

# Stop running container
if docker ps --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
    echo "Stopping running container..."
    docker stop "${CONTAINER_NAME}"
fi

# Remove existing container
if docker ps -a --filter "name=^${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then
    echo "Removing old container..."
    docker rm "${CONTAINER_NAME}"
fi

# Remove existing volume
if docker volume ls --filter "name=pi-agent-data" --format '{{.Name}}' | grep -q "pi-agent-data"; then
    echo "Removing old volume..."
    docker volume rm pi-agent-data
fi

# Create new volume
echo "Creating new volume..."
docker volume create pi-agent-data

# Restore the backup
echo "Extracting backup data..."
docker run --rm \
    -v pi-agent-data:/data \
    -v "$(cd "$(dirname "$BACKUP_FILE")" && pwd):/backup" \
    alpine tar xzf "/backup/$(basename "$BACKUP_FILE")" -C /data

# Recreate container
echo "Creating new container..."
docker run -d \
    --name "${CONTAINER_NAME}" \
    -v pi-agent-data:/root \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "${IMAGE_NAME}" \
    tail -f /dev/null

if [ $? -eq 0 ]; then
    echo "✓ Container restored successfully"
    echo "Start the container with: ./launch.sh"
else
    echo "✗ Restore failed"
    exit 1
fi
