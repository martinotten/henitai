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
    fd-find \
    perl \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME}

# Pi currently requires Node.js >= 22.19.0; Debian trixie ships Node.js 20.
RUN npm install -g n && \
    n 22.19.0 && \
    npm cache clean --force && \
    node --version

# Install AI CLI tools.
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent && \
    npm install -g @openai/codex

COPY .devcontainer/configure-pi-models.sh /usr/local/bin/configure-pi-models
RUN chmod +x /usr/local/bin/configure-pi-models

RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh \
    && mv ~/.local/bin/rtk /usr/local/bin/rtk

# Pre-create and chown Pi's state dir (sessions, models.json) so the
# named volume mounted here (see devcontainer.json) copies up with
# vscode ownership on first mount, instead of defaulting to root.
RUN mkdir -p /home/${USERNAME}/.pi && chown -R ${USER_UID}:${USER_GID} /home/${USERNAME}/.pi

USER ${USERNAME}

WORKDIR /workspace
