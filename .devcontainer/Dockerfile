# Hen'i-tai 変異体 — Dev Container

FROM ruby:4.0.2-alpine

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

# Install system dependencies for Ruby development and native gem builds.
RUN apk add --no-cache \
    bash \
    build-base \
    curl \
    git \
    libffi-dev \
    gdbm-dev \
    libxml2-dev \
    libxslt-dev \
    ncurses-dev \
    nodejs \
    npm \
    openssl-dev \
    readline-dev \
    yaml-dev \
    zlib-dev \
    && npm install -g @openai/codex \
    && addgroup -g ${USER_GID} ${USERNAME} \
    && adduser -D -u ${USER_UID} -G ${USERNAME} -s /bin/bash ${USERNAME}

USER ${USERNAME}

WORKDIR /workspace
