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
    libpq-dev \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Install mise as vscode user
USER vscode

RUN curl https://mise.run | sh \
    && echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc

# Install runtimes via mise
ENV PATH="/home/vscode/.local/bin:${PATH}"
RUN mise use -g ruby@3.4.8 \
    && mise use -g node@22

# Install global tools
SHELL ["/bin/bash", "-c"]
RUN eval "$(mise activate bash)" \
    && gem install bundler \
    && npm install -g @anthropic-ai/claude-code

WORKDIR /workspace