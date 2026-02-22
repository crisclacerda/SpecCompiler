# =============================================================================
# SpecCompiler - Unified Docker Build
#
# Stages:
#   toolchain  — expensive vendor deps (Lua, Pandoc/GHC, Deno, PlantUML, etc.)
#   builder    — alias that pulls the pre-built toolchain from a registry
#   runtime    — lean production image (default target)
#   codeonly   — fast overlay of src/ and models/ onto an existing image
#
# Usage:
#   docker build --target toolchain -t speccompiler-toolchain:latest .
#   docker build --target runtime   -t speccompiler-core:latest \
#       --build-arg TOOLCHAIN_IMAGE=speccompiler-toolchain:latest .
#   docker build --target codeonly  -t speccompiler-core:latest \
#       --build-arg BASE_IMAGE=speccompiler-core:latest .
#
# All versions are pinned in scripts/versions.env.
# =============================================================================

ARG DEBIAN_TAG=bookworm
ARG TOOLCHAIN_IMAGE=ghcr.io/specir/speccompiler-toolchain:latest
ARG BASE_IMAGE=speccompiler-core:latest

# =============================================================================
# Stage: toolchain
# Builds only the expensive vendor dependencies. Rebuilt ONLY when
# toolchain-related files change (versions.env, build_vendor.sh, src/tools/).
# Published to GHCR as speccompiler-toolchain:latest.
# =============================================================================
FROM debian:${DEBIAN_TAG}-slim AS toolchain

# Install ALL build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git curl unzip ca-certificates pkg-config \
    libreadline-dev libgmp-dev libffi-dev zlib1g-dev \
    libzip-dev peg default-jdk-headless graphviz \
    && rm -rf /var/lib/apt/lists/*

# Copy ONLY the files build_vendor.sh actually reads during the build.
# Keeping this set minimal ensures the Docker cache is only invalidated
# when the toolchain itself needs to change.
COPY scripts/versions.env        /build/scripts/versions.env
COPY scripts/build_vendor.sh     /build/scripts/build_vendor.sh
COPY src/tools/amath/            /build/src/tools/amath/
COPY src/tools/echarts-render.ts /build/src/tools/echarts-render.ts
COPY src/tools/mml2omml.ts       /build/src/tools/mml2omml.ts

# Build everything: Lua, Pandoc (via GHCup/Cabal), Deno, PlantUML, SQLite,
# all Lua C extensions (lsqlite3, luv, brimworks/zip, luaamath), and pure Lua
# libraries. Also caches Deno TypeScript dependencies.
ENV GHCUP_PREFIX=/opt
RUN bash /build/scripts/build_vendor.sh \
    --skip-system-deps \
    --prefix /opt/speccompiler \
    --source-dir /build

# =============================================================================
# Stage: builder
# Uses the pre-built toolchain image so that the expensive Pandoc/GHC
# compilation is never re-triggered by ordinary source-code changes.
# The toolchain stage above is rebuilt separately only when
# scripts/versions.env, build_vendor.sh, or src/tools/ change.
# =============================================================================
FROM ${TOOLCHAIN_IMAGE} AS builder

# =============================================================================
# Stage: runtime — lean production image (default target)
# =============================================================================
FROM debian:${DEBIAN_TAG}-slim AS runtime

# Runtime-only packages (no -dev packages, no build tools)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgmp10 \
    libffi8 \
    zlib1g \
    libzip4 \
    graphviz \
    lcov \
    ca-certificates \
    bash \
    zip \
    unzip \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages needed by ReqIF exporter
RUN python3 -m pip install --break-system-packages --no-cache-dir reqif

# Create an unprivileged runtime user.
RUN groupadd --system --gid 10001 speccompiler \
    && useradd --system --uid 10001 --gid speccompiler \
        --create-home --home-dir /home/speccompiler --shell /usr/sbin/nologin speccompiler

WORKDIR /opt/speccompiler

# All build artifacts from the toolchain
COPY --from=builder /opt/speccompiler/bin/     ./bin/
COPY --from=builder /opt/speccompiler/vendor/  ./vendor/
COPY --from=builder /opt/speccompiler/jre/     ./jre/
# Ensure liblua5.4.so.0 symlink exists (pandoc compiled with +system-lua expects this soname)
RUN ln -sf /opt/speccompiler/vendor/lua/lib/liblua5.4.so \
           /opt/speccompiler/vendor/lua/lib/liblua5.4.so.0

# Application source and models
COPY src/    ./src/
COPY models/ ./models/

# Ensure /opt/speccompiler/bin is on PATH even in login shells (which reset PATH via /etc/profile)
RUN echo 'export PATH="/opt/speccompiler/bin:$PATH"' > /etc/profile.d/specc.sh

# Environment setup
ENV SPECCOMPILER_HOME=/opt/speccompiler
ENV SPECCOMPILER_DIST=/opt/speccompiler
ENV DENO_DIR=/opt/speccompiler/vendor/deno_cache
ENV LD_LIBRARY_PATH="/opt/speccompiler/vendor/lua/lib"
ENV LUA_PATH="/opt/speccompiler/src/?.lua;/opt/speccompiler/src/?/init.lua;/opt/speccompiler/?.lua;/opt/speccompiler/?/init.lua;/opt/speccompiler/vendor/?.lua;/opt/speccompiler/vendor/?/init.lua;/opt/speccompiler/vendor/slaxml/?.lua"
ENV LUA_CPATH="/opt/speccompiler/vendor/?.so;/opt/speccompiler/vendor/?/?.so"
ENV PATH="/opt/speccompiler/bin:${PATH}"
ENV HOME=/home/speccompiler

RUN mkdir -p /workspace \
    && chown -R speccompiler:speccompiler /opt/speccompiler /workspace /home/speccompiler

USER speccompiler

WORKDIR /workspace

# =============================================================================
# Stage: codeonly — fast overlay of src/ and models/ onto an existing image.
# Used by: scripts/docker_install.sh --code-only
# Requires the base speccompiler-core:latest image to already exist locally.
# =============================================================================
FROM ${BASE_IMAGE} AS codeonly
COPY src/    /opt/speccompiler/src/
COPY models/ /opt/speccompiler/models/
