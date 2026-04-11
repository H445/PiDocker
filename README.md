# Pi Coding Agent Docker Container

A containerized, reproducible development environment for the [pi coding agent](https://github.com/badlogic/pi-mono)—an AI-powered tool that reads, writes, and modifies code with near-complete autonomy.

> **Backstory:** I had a pi-agent nuke itself and didn't want to deal with setting up another bare-metal instance. This project wraps pi in Docker so you can build, configure, and run it with full isolation. It's a complete skeleton—modify it to suit your needs.

## Why Docker?

- **Reproducible environment** — Consistent setup across machines
- **Safe experimentation** — Isolated container keeps your host system clean
- **Easy persistence** — Named volume preserves all state and configuration
- **Quick backups** — Built-in backup and restore for your work
- **Local LLM support** — Use local models via LMStudio or Ollama alongside cloud APIs

## Prerequisites

- [Docker](https://www.docker.com/) installed and running
- An LLM API key (OpenAI, Anthropic, Google, etc.) **or** a local LLM provider

## Quick Start

```bash
# Linux / macOS
./run.sh

# Windows PowerShell
.\run.ps1
```

On Windows, the PowerShell scripts run Docker commands directly (no WSL requirement).

This opens an interactive management menu:

| Option | Description |
|--------|-------------|
| **[1]** Launch pi | Start or resume an interactive pi session |
| **[2]** Launch pi with extensions | Load custom extensions on startup |
| **[3]** Open container shell | Open an interactive shell (`bash` or `sh`) without launching pi |
| **[4]** Build image | Build or rebuild the Docker image (starts container automatically) |
| **[5]** Provider configuration | Configure local LLM providers (LMStudio, Ollama) |
| **[6]** Backup management | Create, list, restore, or delete backups |
| **[7]** Container management | Stop, remove, or view container status |

### First-Time Setup

1. Run `./run.sh` (or `.\run.ps1`) → **[4]** to build the Docker image
   - This builds the image and automatically starts the container
2. *(Optional)* **[5]** to configure local LLM providers
   - The container must be running to configure providers
3. **[1]** to launch pi
4. Inside pi, type `/login` to authenticate with your LLM provider
5. Start coding!

### Direct Script Access

You can also run individual scripts directly:

```bash
./build.sh              # Build the Docker image (starts container automatically)
./localprovider.sh      # Configure local LLM providers
./launch.sh             # Launch/resume pi agent
./backup.sh             # Create a backup
./restore.sh            # Restore from backup
```

On Windows PowerShell, use the `.ps1` versions of each script.

## Usage

Once inside the container via **[1] Launch pi**, interact with the agent:

```
/read src/main.ts          # Read files
/write src/main.ts         # Write code
/edit src/main.ts          # Edit files
/bash npm test             # Execute commands
/bash npm install express  # Install packages
```

### Container Shell Access

Use menu option **[3]** to open an interactive shell directly in the container (`bash` when available, otherwise `sh`). This is useful for:

- Installing system packages or dependencies
- Installing pi extensions via `pi install npm:@scope/package-name`
- Inspecting files and debugging issues
- Running custom scripts or commands

Type `exit` to return to the menu.

#### Installing Extensions

To install a pi extension from the container shell, use the pi package manager:

```bash
pi install npm:@foo/pi-tools
```

Extensions are installed to `~/.pi/extensions/` and will be available for use in pi sessions. You can then load them with option **[2] Launch pi with extensions** from the menu.

## Configuration

Pi stores its configuration in `~/.pi/` inside the container. On first launch, it will prompt you to set up your LLM provider and API key. This is automatically persisted in the named volume.

### Built-in Providers

Pi supports major LLM providers out of the box:

- **OpenAI** (GPT-4, GPT-3.5)
- **Anthropic** (Claude)
- **Google** (Gemini)
- And more…

Configure these through pi's interactive setup on first launch, or use `/login` in an active session.

### Local LLM Providers

Use menu option **[5]** (or run `./localprovider.sh` / `.\localprovider.ps1` directly) to configure local models from LMStudio or Ollama.

The configuration menu lets you:

- **Configure LMStudio** — Add models from `http://localhost:1234/v1`
- **Configure Ollama** — Add models from `http://localhost:11434/v1`
- **View current config** — Display saved provider configurations
- **Clear all providers** — Remove all custom provider configurations

The script polls your running provider for available models, lets you select which ones to add, and saves the configuration to `~/.pi/agent/models.json` inside the container.

#### Host Access from Container

When your LLM provider runs on the **host machine** (not in a container), the container needs a special hostname to reach it:

| Platform | URL Pattern |
|----------|-------------|
| **Docker Desktop (Windows/Mac)** | `http://host.docker.internal:PORT/v1` |
| **Linux** | `http://<host-ip>:PORT/v1` |

Examples:

- LMStudio: `http://host.docker.internal:1234/v1`
- Ollama: `http://host.docker.internal:11434/v1`

The scripts default to `host.docker.internal`, which works on Docker Desktop.

To inspect the config from outside the container:

```bash
docker exec pi-agent cat /root/.pi/agent/models.json
```

## Persistence

All data is stored in a Docker named volume (`pi-agent-data`) mounted at `/root` in the container:

- Pi configuration (`.pi/` directory)
- Files you create and edit
- Session history
- Installed packages and environment state
- Local provider configurations

The container runs in the background even after you exit the interactive session.

## Backup & Restore

Use menu option **[6]** for full backup management, or run the scripts directly:

```bash
./backup.sh                                                  # Create a backup
./restore.sh                                                 # List available backups
./restore.sh backups/pi-agent-backup-20250115_143022.tar.gz  # Restore a specific backup
```

Backups are saved as timestamped `.tar.gz` archives in the `backups/` directory.

### Automated Backups

```bash
# Add to crontab (crontab -e)
0 3 * * * /path/to/pi-docker/backup.sh
```

## Container Management

Use menu option **[7]**, or manage directly with Docker:

```bash
docker stop pi-agent                     # Stop the container
docker rm pi-agent                       # Remove the container (volume is preserved)
docker ps -a --filter "name=pi-agent"    # View container status
```

Removing the container does **not** delete the volume. Recreate the container and your data will still be there.

### Full Cleanup

To remove everything (container, volume, and all data):

```bash
docker stop pi-agent
docker rm pi-agent
docker volume rm pi-agent-data
```

Backups in the `backups/` directory are unaffected and can be used to restore later.

## Files

| File | Description |
|------|-------------|
| `Dockerfile` | Node.js 20 Alpine image with native build deps and workspace build steps for pi coding-agent |
| `run.sh` / `run.ps1` | Interactive management menu |
| `build.sh` / `build.ps1` | Builds the Docker image and starts the container |
| `launch.sh` / `launch.ps1` | Launches or resumes the pi container |
| `localprovider.sh` / `localprovider.ps1` | Configures local LLM providers |
| `backup.sh` / `backup.ps1` | Creates timestamped backups |
| `restore.sh` / `restore.ps1` | Restores from backup |

> **Note:** The container runs as root with full system access—install packages, modify files, and run arbitrary commands freely.

## Links & Credits

Pi is an AI coding agent created by [Mario Zechner](https://github.com/badlogic) at badlogic.

- **GitHub:** [pi-mono](https://github.com/badlogic/pi-mono) — The full monorepo
- **Website:** [shittycodingagent.ai](https://shittycodingagent.ai/)
- **Discord:** [badlogic Discord](https://discord.com/invite/3cU7Bz4UPx)

This Docker wrapper is a community contribution—not affiliated with badlogic. Contributions and feedback welcome!
