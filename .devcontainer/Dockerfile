# Hen'i-tai 変異体 — Dev Container
# Ruby 4.0.2 via mise (formerly rtx)

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG RUBY_VERSION=4.0.2
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    libffi-dev \
    libgdbm-dev \
    libncurses5-dev \
    libreadline-dev \
    libssl-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install mise (version manager) as vscode user
USER ${USERNAME}

RUN curl https://mise.run | sh && \
    echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc && \
    echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.profile

# Install Ruby 4.0.2 via mise
RUN ~/.local/bin/mise install ruby@${RUBY_VERSION} && \
    ~/.local/bin/mise use --global ruby@${RUBY_VERSION}

# Install Bundler
RUN ~/.local/bin/mise exec -- gem install bundler --no-document

# Ensure mise-managed Ruby is on PATH
ENV PATH="/home/${USERNAME}/.local/share/mise/shims:${PATH}"

WORKDIR /workspace
