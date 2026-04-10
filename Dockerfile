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

# Install pi globally so `pi` is available on PATH.
RUN npm install -g @mariozechner/pi-coding-agent@latest

# Set working directory to root for agent access
WORKDIR /root

# Run as root to allow full container access
USER root

# Default command: interactive shell
CMD ["/bin/bash"]
