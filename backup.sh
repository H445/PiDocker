#!/bin/bash
# Backup the persistent pi-agent container

CONTAINER_NAME="pi-agent"
BACKUP_DIR="backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/pi-agent-backup-${TIMESTAMP}.tar.gz"

# Create backups directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Check if container/volume exists
if ! docker volume ls --filter "name=pi-agent-data" --format '{{.Name}}' | grep -q "pi-agent-data"; then
    echo "✗ No container or volume found. Nothing to backup."
    exit 1
fi

echo "Creating backup: ${BACKUP_FILE}"

# Export the volume data
docker run --rm \
    -v pi-agent-data:/data \
    -v "$(pwd)/${BACKUP_DIR}:/backup" \
    alpine tar czf "/backup/pi-agent-backup-${TIMESTAMP}.tar.gz" -C /data .

if [ $? -eq 0 ]; then
    echo "✓ Backup created: ${BACKUP_FILE}"
    ls -lh "${BACKUP_FILE}"
else
    echo "✗ Backup failed"
    exit 1
fi
