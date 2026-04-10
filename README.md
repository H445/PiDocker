# Pi Coding Agent Docker Container

**Why this exists:** Run pi-agent in YOLO mode inside an isolated, reproducible Docker environment.

This project provides a containerized setup that keeps pi-agent contained and easy to manage.

## Prerequisites

- Docker installed and running
- Bash shell (for scripts)
- An LLM API key (e.g., OpenAI, Claude, etc.) for pi to function

## Quick Start

### 1. Build the Image

```bash
./build.sh
```

On Windows PowerShell:

```powershell
.\build.ps1
```

This creates a Docker image named `pi-agent:latest` with all dependencies installed and the coding agent ready to use.

### 2. Launch the Agent

```bash
./launch.sh
```

On Windows PowerShell:

```powershell
.\launch.ps1
```

This starts an interactive pi session. On first run, it creates a persistent container and named volume. On subsequent runs, it reuses the same container, preserving all state, files, and configurations.

### Optional: Use the Menu Launcher

```bash
./run.sh
```

On Windows PowerShell:

```powershell
.\run.ps1
```

This opens an interactive menu for launch/build plus two submenus:
- **Backup Management**: create, list, restore, and delete backups
- **Container Management**: stop container, remove container (keep volume), and view status

### 3. Stop the Agent

Exit the pi terminal with `Ctrl+C` or type `exit`. The container remains running in the background for quick restart.

```bash
./launch.sh  # Restart and resume
```

## Persistence

All data is stored in a Docker named volume (`pi-agent-data`) mounted to `/root` in the container. This includes:
- Pi configuration (`.pi` directory)
- All files you create/edit
- Session history
- Installed packages
- Environment state

The container runs continuously in the background, even when you exit the interactive session.

### Stop the Container

```bash
docker stop pi-agent
```

### Remove the Container (but keep data)

```bash
docker rm pi-agent
```

The volume persists. You can recreate the container and your data will be restored.

### View Container Status

```bash
docker ps -a --filter "name=pi-agent"
```

## Backup and Restore

You can run backup operations directly (`./backup.sh`, `./restore.sh`) or through the `run.sh` / `run.ps1` **Backup Management** submenu.

### Create a Backup

```bash
./backup.sh
```

Creates a compressed archive in the `backups/` directory with timestamp (e.g., `pi-agent-backup-20250115_143022.tar.gz`).

### List Available Backups

```bash
./restore.sh
```

Shows all available backup files with timestamps.

### Restore from Backup

```bash
./restore.sh backups/pi-agent-backup-20250115_143022.tar.gz
```

This will:
1. Stop the running container (if any)
2. Remove the old container and volume
3. Create a new volume from the backup
4. Recreate the container with restored data

Then start it again:
```bash
./launch.sh
```

### Automated Backups

Create a cron job for daily backups:

```bash
# Add to crontab (crontab -e)
0 3 * * * /path/to/pi-docker/backup.sh
```

## Files

- **Dockerfile** - Builds a Node.js 20 Alpine image with pi coding-agent
- **build.sh** - Builds the Docker image (`pi-agent:latest`)
- **build.ps1** - PowerShell build script for the image on Windows
- **launch.sh** - Launches/resumes persistent pi container
- **launch.ps1** - PowerShell wrapper for launching/resuming pi on Windows
- **backup.sh** - Creates timestamped backups of container data
- **backup.ps1** - PowerShell backup script for container data on Windows
- **restore.sh** - Restores container from backup
- **restore.ps1** - PowerShell restore script on Windows
- **run.sh** - Interactive Bash menu for all management operations
- **run.ps1** - Interactive PowerShell menu for all management operations
- **README.md** - This file

## Root Access

The container runs as root with full system access to:
- Install packages
- Modify system files
- Run arbitrary commands
- Access Docker daemon (via mounted socket)

## Usage Examples

Once inside the container via `./launch.sh`, use pi:

```
pi
```

Then interact with the agent. Ask it to:
- Read files: `/read src/main.ts`
- Execute commands: `/bash npm test`
- Write code: `/write src/main.ts`
- Edit files: `/edit src/main.ts`
- Install packages: `/bash npm install express`

## Configuration

Pi stores configuration in `~/.pi/` inside the container. On first run, pi will prompt you to configure your LLM provider and API key. This is automatically persisted in the named volume.

To view or edit config from outside the container:
```bash
docker exec pi-agent cat /root/.pi/config.json
```

## Cleanup

To completely remove the container, volume, and all data:

```bash
docker stop pi-agent
docker rm pi-agent
docker volume rm pi-agent-data
```

Backups in the `backups/` directory remain and can be used to restore later.

## Links

- [pi Documentation](https://pi.dev)
- [GitHub Repository](https://github.com/badlogic/pi-mono)
- [Discord Community](https://discord.com/invite/3cU7Bz4UPx)
