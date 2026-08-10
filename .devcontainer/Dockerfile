FROM mcr.microsoft.com/devcontainers/base:debian

# System dependencies for Ruby/Rails compilation
RUN apt-get update && apt-get install -y \
    build-essential \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libffi-dev \
    libyaml-dev \
    libgdbm-dev \
    libncurses5-dev \
    libgmp-dev \
    autoconf \
    bison \
    rustc \
    cargo \
    redis-tools \
    libpq-dev \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Install mise as vscode user
USER vscode

RUN curl https://mise.run | sh \
    && echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc

# Install runtimes via mise
ENV PATH="/home/vscode/.local/bin:${PATH}"
RUN mise use -g ruby@3.4.10 \
    && mise use -g node@22

# Install global tools
SHELL ["/bin/bash", "-c"]
RUN eval "$(mise activate bash)" \
    && gem install bundler \
    && gem install foreman --no-document \
    && npm install -g @anthropic-ai/claude-code

# Cypress/Electron runtime dependencies
# Debian 13 (trixie) renamed several of these in the 64-bit time_t transition, hence the
# t64 suffixes — the apt line from the Cypress docs targets bookworm and will not resolve here.
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    xauth \
    libgtk-3-0t64 \
    libnotify4 \
    libnss3 \
    libxss1 \
    libasound2t64 \
    libxtst6 \
    libgbm1 \
    libatk1.0-0t64 \
    libatk-bridge2.0-0t64 \
    libatspi2.0-0t64 \
    libcups2t64 \
    libdrm2 \
    libdbus-1-3 \
    libglib2.0-0t64 \
    libcairo2 \
    libpango-1.0-0 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libxfixes3 \
    libxext6 \
    libx11-xcb1 \
    libxkbcommon0 \
    fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

USER vscode

# VS Code's extension host exports ELECTRON_RUN_AS_NODE=1, which leaks into shells it spawns
# and makes Cypress's Electron binary start as plain Node — it then rejects Cypress's own
# flags with "bad option: --no-sandbox". Inserted at line 1 rather than appended because
# stock .bashrc returns early for non-interactive shells before reaching the end.
RUN sed -i '1i unset ELECTRON_RUN_AS_NODE  # keeps Cypress'"'"'s Electron out of node mode' ~/.bashrc

# Mount points for the named volumes in docker-compose.yml. These must exist in the image and
# be vscode-owned: Docker creates a missing mount point as root, leaving it unwritable.
RUN mkdir -p /home/vscode/.cache/Cypress /home/vscode/.claude

WORKDIR /workspace
