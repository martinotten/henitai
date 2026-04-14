# Hen'i-tai 変異体 — Dev Container

FROM ruby:4

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

# Install system dependencies for Ruby development and native gem builds.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    jq \
    libffi-dev \
    libgdbm-dev \
    libxml2-dev \
    libxslt-dev \
    libncurses-dev \
    python3 \
    nodejs \
    npm \
    libssl-dev \
    libreadline-dev \
    libyaml-dev \
    zlib1g-dev \
    ripgrep \
    perl \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g @openai/codex \
    && curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh \
    && ln -s /root/.local/bin/rtk /usr/local/bin/rtk \
    && groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME}

USER ${USERNAME}

WORKDIR /workspace
