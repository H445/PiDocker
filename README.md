# Pi Coding Agent Docker Container

**The story:** I recently had a pi-agent nuke itself. I didn't want to go through the hassle of containerizing another one-off that would nuke itself again, so here we are. A ready-to-go Docker containerized pi-agent. Just configure, build, and run. Following the core of pi-agent, it is a complete skeleton—it's up to you to modify it from here.

**What this is:** A containerized, reproducible development environment for the pi coding agent—an AI-powered tool that reads, writes, and modifies code with near-complete autonomy.

**Why this exists:** Pi is powerful but needs careful setup and isolation. This project wraps pi in Docker to provide:
- **Reproducible environment** - Consistent setup across machines
- **Safe experimentation** - Isolated container keeps your system clean
- **Easy persistence** - Named volume preserves all state and configurations
- **Quick backups** - Built-in backup/restore for your work
- **Local LLM support** - Use local models via LMStudio or Ollama alongside cloud APIs

Run pi-agent in YOLO mode inside an isolated, reproducible Docker environment.

## Prerequisites

- Docker installed and running
- Bash shell (for scripts)
- An LLM API key (e.g., OpenAI, Claude, etc.) for pi to function

## Quick Start

Use the management menu to handle everything:

```bash
./run.sh
```

On Windows PowerShell:

```powershell
.\run.ps1
```

This opens an interactive menu with all operations in order:

- **[1] Launch pi** - Start/resume an interactive pi session
- **[2] Launch pi with extensions** - Load custom extensions on startup
- **[3] Build image** - Build/rebuild the Docker image
- **[4] Provider configuration** - Configure local LLM providers (LMStudio, Ollama)
- **[5] Backup management** - Create, list, restore, or delete backups
- **[6] Container management** - Stop, remove, or view container status

### Recommended Workflow

1. **First time**: Run `./run.sh` → Option **[3]** to build the image
2. **Configure providers** (optional): Option **[4]** to add local LLM models
3. **Launch pi**: Option **[1]** to start an interactive session
4. **Login in pi**: Type `/login` and follow prompts to authenticate with your LLM provider
5. **Start coding**: Begin using pi to read, write, and edit code

### Direct Script Access

You can also run individual scripts directly if needed:

```bash
./build.sh              # Build the Docker image
./localprovider.sh      # Configure local LLM providers
./launch.sh             # Launch/resume pi agent
./backup.sh             # Create a backup
./restore.sh            # Restore from backup
```

On Windows PowerShell, use `.ps1` versions of the scripts.

## Local LLM Provider Configuration

To configure local LLM providers (LMStudio, Ollama), use the menu option **[4] Provider configuration** in `./run.sh` or `./run.ps1`, or run directly:

```bash
./localprovider.sh
```

This opens an interactive menu to:
- **Configure LMStudio** - Add models from LMStudio running on `http://localhost:1234/v1`
- **Configure Ollama** - Add models from Ollama running on `http://localhost:11434/v1`
- **View current config** - Display saved provider configurations
- **Clear all providers** - Remove all custom provider configurations

### How It Works

1. The script polls your running LM provider for available models
2. You select which models to add (by number)
3. Configuration is saved to `~/.pi/agent/models.json` inside the container
4. Models are immediately available in pi

### Important: Host Access from Container

When running providers on your **host machine** (not in a container), use these URLs:

- **Docker Desktop (Windows/Mac)**: `http://host.docker.internal:PORT/v1`
  - LMStudio: `http://host.docker.internal:1234/v1`
  - Ollama: `http://host.docker.internal:11434/v1`

- **Linux**: Use your host machine's IP address
  - LMStudio: `http://<host-ip>:1234/v1`
  - Ollama: `http://<host-ip>:11434/v1`

The default values in the script use `host.docker.internal`, which works on Docker Desktop.

## Persistence

All data is stored in a Docker named volume (`pi-agent-data`) mounted to `/root` in the container. This includes:
- Pi configuration (`.pi` directory)
- All files you create/edit
- Session history
- Installed packages
- Environment state
- Local provider configurations

The container runs continuously in the background, even when you exit the interactive session.

### Stop the Container

Use menu option **[6] Container management** → **[1] Stop container**, or:

```bash
docker stop pi-agent
```

### Remove the Container (but keep data)

Use menu option **[6] Container management** → **[2] Remove container**, or:

```bash
docker rm pi-agent
```

The volume persists. You can recreate the container and your data will be restored.

### View Container Status

Use menu option **[6] Container management** → **[3] Container status**, or:

```bash
docker ps -a --filter "name=pi-agent"
```

## Backup and Restore

Use menu option **[5] Backup management** to create, list, restore, or delete backups.

### Create a Backup

Menu option **[5]** → **[1] Create backup**, or directly:

```bash
./backup.sh
```

Creates a compressed archive in the `backups/` directory with timestamp.

### List Available Backups

Menu option **[5]** → **[2] List backups**, or:

```bash
./restore.sh
```

### Restore from Backup

Menu option **[5]** → **[3] Restore backup** and select from the list.

Or restore directly:

```bash
./restore.sh backups/pi-agent-backup-20250115_143022.tar.gz
```

Then launch again:

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
- **build.sh / build.ps1** - Builds the Docker image
- **launch.sh / launch.ps1** - Launches/resumes persistent pi container
- **backup.sh / backup.ps1** - Creates timestamped backups of container data
- **restore.sh / restore.ps1** - Restores container from backup
- **run.sh / run.ps1** - Interactive menu for all management operations
- **localprovider.sh / localprovider.ps1** - Configures local LLM providers
- **README.md** - This file

## Root Access

The container runs as root with full system access to:
- Install packages
- Modify system files
- Run arbitrary commands
- Access Docker daemon (via mounted socket)

## Usage Examples

Once inside the container via menu option **[1] Launch pi**, use pi:

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

Pi stores configuration in `~/.pi/` inside the container. On first launch, pi will prompt you to configure your LLM provider and API key. This is automatically persisted in the named volume.

### Built-in Providers

Pi comes with support for major LLM providers:
- OpenAI (GPT-4, GPT-3.5)
- Anthropic (Claude)
- Google (Gemini)
- And more...

Configure these through pi's interactive setup when you first launch it, or use `/login` in an active pi session.

### Local Providers

To use local models via LMStudio or Ollama, use menu option **[4] Provider configuration**.

To view or edit the config from outside the container:
```bash
docker exec pi-agent cat /root/.pi/agent/models.json
```

## Cleanup

To completely remove the container, volume, and all data:

```bash
docker stop pi-agent
docker rm pi-agent
docker volume rm pi-agent-data
```

Backups in the `backups/` directory remain and can be used to restore later.

## Links & Credits

### About Pi

Pi is an AI coding agent that can read, write, edit, and understand code with remarkable autonomy. It's the creation of [Mario Zechner](https://github.com/badlogic) at badlogic.

- **GitHub**: [pi-mono](https://github.com/badlogic/pi-mono) - The full monorepo with all pi packages
- **Website**: [shittycodingagent.ai](https://shittycodingagent.ai/) - Learn more about pi's capabilities
- **Discord Community**: [badlogic Discord](https://discord.com/invite/3cU7Bz4UPx) - Chat with Mario and the community

### This Project

This Docker wrapper is a community contribution to make pi easier to use and experiment with. It's not affiliated with badlogic, but aims to be a useful companion to the main pi project.

Contributions and feedback welcome!
