FROM node:20-alpine

ARG PI_PACKAGE_NAME=@mariozechner/pi-coding-agent
ARG PI_PACKAGE_VERSION=latest

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

# Install the latest published pi package globally.
# --force ensures npm replaces any previously bundled version cleanly.
RUN npm install -g --force "${PI_PACKAGE_NAME}@${PI_PACKAGE_VERSION}" && \
    pi --version

# Set working directory to root for agent access
WORKDIR /root

# Run as root to allow full container access
USER root

# Default command: interactive shell
CMD ["/bin/bash"]
