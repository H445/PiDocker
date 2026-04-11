FROM node:20-alpine

# Install additional dependencies for the agent
RUN apk add --no-cache \
    bash \
    git \
    curl \
    jq \
    python3 \
    build-base \
    pkgconf \
    pixman-dev \
    cairo-dev \
    pango-dev \
    jpeg-dev \
    giflib-dev \
    librsvg-dev

WORKDIR /app

# Clone the pi-mono repository
RUN git clone https://github.com/badlogic/pi-mono.git /app

# Install dependencies from monorepo root (workspace scripts expect root tooling)
WORKDIR /app
RUN npm install

# Build required workspace packages in dependency order
WORKDIR /app
RUN npm --workspace packages/tui run build && \
    npm --workspace packages/ai run build && \
    npm --workspace packages/agent run build && \
    npm --workspace packages/coding-agent run build

# Create a symlink so 'pi' is available globally
RUN ln -s /app/packages/coding-agent/dist/cli.js /usr/local/bin/pi && \
    chmod +x /usr/local/bin/pi

# Set working directory to root for agent access
WORKDIR /root

# Run as root to allow full container access
USER root

# Default command: interactive shell
CMD ["/bin/bash"]
