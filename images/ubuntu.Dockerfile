FROM ubuntu:24.04 AS build

ARG TARGETOS=linux
ARG RUNNER_ARCH=x64
ARG RUNNER_VERSION=2.325.0
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.7.0
ARG DOCKER_VERSION=28.2.2
ARG DOCKER_ARCH=x86_64
ARG COMPOSE_VERSION=2.36.2
ARG BUILDX_VERSION=0.24.0
ARG BUILDX_ARCH=amd64

RUN apt update && apt install -y curl unzip

WORKDIR /actions-runner
RUN curl -s -f -o runner.tar.gz -L "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${TARGETOS}-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" \
  && tar xzf ./runner.tar.gz \
  && rm runner.tar.gz

RUN curl -s -f -o runner-container-hooks.zip -L "https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip" \
  && unzip ./runner-container-hooks.zip -d ./k8s \
  && rm runner-container-hooks.zip

RUN curl -s -f -o docker.tgz -L "https://download.docker.com/${TARGETOS}/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz" \
  && tar zxvf docker.tgz \
  && rm -rf docker.tgz

RUN mkdir -p /usr/local/lib/docker/cli-plugins \
  && curl -s -f -o /usr/local/lib/docker/cli-plugins/docker-buildx \
  -L "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-${BUILDX_ARCH}" \
  && chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

RUN curl -s -f -o /usr/local/lib/docker/cli-plugins/docker-compose \
  -L "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-${DOCKER_ARCH}" \
  && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1
ENV ImageOS=ubuntu24

RUN apt update \
  && apt upgrade -y \
  && apt install -y --no-install-recommends \
  sudo \
  lsb-release \
  git \
  adduser \
  curl \
  jq \
  unzip \
  libicu-dev \
  libssl-dev \
  build-essential \
  python3 \
  python3-pip \
  pipx \
  libpq-dev \
  && rm -rf /var/lib/apt/lists/*

RUN adduser --disabled-password --gecos "" --uid 1001 runner \
  && groupadd docker --gid 123 \
  && usermod -aG sudo runner \
  && usermod -aG docker runner \
  && echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers \
  && echo "Defaults env_keep += \"DEBIAN_FRONTEND\"" >> /etc/sudoers

WORKDIR /home/runner

COPY --from=build --chown=runner:docker /actions-runner .
COPY --from=build /usr/local/lib/docker/cli-plugins/docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx
COPY --from=build /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose

RUN install -o root -g root -m 755 docker/* /usr/bin/ && rm -rf docker

USER runner

RUN python3 --version \
  && pipx install poetry \
  && pipx ensurepath \
  && sudo ln -s /root/.local/bin/poetry /usr/bin/poetry

RUN sudo ./bin/installdependencies.sh && sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/*
