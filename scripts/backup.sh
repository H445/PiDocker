#!/bin/bash
# Backup the persistent pi-agent container

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_config.sh"

BACKUP_DIR="$(dirname "$SCRIPT_DIR")/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/${CONTAINER_NAME}-backup-${TIMESTAMP}.tar.gz"

# Create backups directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Check if container/volume exists
if ! docker volume ls --format '{{.Name}}' | grep -qx "$VOLUME_NAME"; then
    echo "✗ No $VOLUME_NAME volume found. Nothing to backup."
    exit 1
fi

echo "Creating backup: ${BACKUP_FILE}"

# Export the volume data
docker run --rm \
    -v "${VOLUME_NAME}:/data" \
    -v "${BACKUP_DIR}:/backup" \
    alpine tar czf "/backup/${CONTAINER_NAME}-backup-${TIMESTAMP}.tar.gz" -C /data .

if [ $? -eq 0 ]; then
    echo "✓ Backup created: ${BACKUP_FILE}"
    ls -lh "${BACKUP_FILE}"
else
    echo "✗ Backup failed"
    exit 1
fi
