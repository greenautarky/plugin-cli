ARG BUILD_FROM

# The ha CLI, built from its release tag with a current Go toolchain. Upstream
# stopped publishing an armv7 binary after 4.42.0, and the published 4.42.0
# binary was built with a Go release that is no longer maintained.
# Cross-compiled on the build host; the output is a static armv7 binary.
# hadolint ignore=DL3029
FROM --platform=amd64 golang:1.26.8-alpine@sha256:8ac98ca534ac3f51e1f420a1dd2c15e74c75cfa0f23f3ad27eb5d7236c349a0c AS cli-builder
SHELL ["/bin/ash", "-o", "pipefail", "-c"]
ARG CLI_VERSION
ENV GOTOOLCHAIN=local
WORKDIR /usr/src
RUN \
    apk add --no-cache git \
    && git clone --depth 1 -b "${CLI_VERSION}" https://github.com/home-assistant/cli \
    && cd cli \
    && CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 go build -trimpath -ldflags="-s -w" -o /usr/src/ha \
    && go version -m /usr/src/ha | head -2

FROM $BUILD_FROM

# Set shell
SHELL ["/bin/ash", "-o", "pipefail", "-c"]

ARG BUILD_ARCH
WORKDIR /usr/src

# The armv7 base image is no longer rebuilt upstream, so its Alpine packages
# only age. Pull the current 3.22 package updates on top of it.
# hadolint ignore=DL3017
RUN apk upgrade --no-cache

# tempio from its current release (the base image carries an older build).
# Checksum-pinned; only the armv7 binary is pinned because only armv7 is built.
ARG TEMPIO_VERSION=2026.07.0
ARG TEMPIO_SHA256=1887c4721317ee166de703ddb30f906c9f98f01f08a6b2da295c10946a0c8110
RUN \
    curl -Lfso /usr/bin/tempio "https://github.com/home-assistant/tempio/releases/download/${TEMPIO_VERSION}/tempio_${BUILD_ARCH}" \
    && echo "${TEMPIO_SHA256}  /usr/bin/tempio" | sha256sum -c - \
    && chmod a+x /usr/bin/tempio

# Install rlwrap
ARG RLWRAP_VERSION
RUN apk add --no-cache --virtual .build-deps \
        build-base \
        readline-dev \
        ncurses-dev \
    && curl -L -s "https://github.com/hanslub42/rlwrap/releases/download/${RLWRAP_VERSION}/rlwrap-${RLWRAP_VERSION}.tar.gz" \
        | tar zxvf - -C /usr/src/ \
    && cd rlwrap-${RLWRAP_VERSION} \
    && ./configure \
    && make \
    && make install \
    && apk del .build-deps \
    && rm -rf /usr/src/*

# Install CLI
COPY --from=cli-builder /usr/src/ha /usr/bin/ha

COPY rootfs /
WORKDIR /
