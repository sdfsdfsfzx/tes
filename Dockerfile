# =============================================================================
# VerusCoin (VRSC) CPU miner for Railway
#
# Multi-stage build:
#   Stage 1 (builder) compiles the official VerusCoin `nheqminer` from source.
#   Stage 2 (runtime) ships only the stripped binary + entrypoint into a bare
#   Ubuntu 22.04 image (~40 MB). The miner links statically against Boost, so
#   the runtime needs no extra packages.
#
# Build args:
#   NHEQMINER_REF  upstream commit to build (pinned for reproducible builds)
# =============================================================================

# --- Builder -----------------------------------------------------------------
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Build dependencies. nheqminer only needs the VerusHash CPU solver (enabled by
# default) and links Boost statically, so we install just the required dev
# packages — no CUDA, no fasm, no OpenSSL.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        git \
        patch \
        libboost-system-dev \
        libboost-log-dev \
        libboost-date-time-dev \
        libboost-filesystem-dev \
        libboost-thread-dev \
    && rm -rf /var/lib/apt/lists/*

ARG NHEQMINER_REF=0b46244021a83a3adba6648e21cc11ad0aa90ee5

WORKDIR /build
RUN git clone https://github.com/VerusCoin/nheqminer.git \
    && cd nheqminer \
    && git checkout ${NHEQMINER_REF}

# Upstream targets Boost ~1.65. Modern GCC (>=8) rejects the combination of
# `#pragma pack(1)` and `__attribute__((aligned(64)))` used in blake2.h. The
# patch restructures the pack regions so only the wire-format param structs stay
# packed, and drops the state structs' alignment from 64 to 8 (their sizes are
# 192/200 bytes, not multiples of 64). See patches/blake2-modern-gcc.patch.
COPY patches/blake2-modern-gcc.patch /build/nheqminer/
RUN cd nheqminer && patch -p1 < blake2-modern-gcc.patch

# -j2 keeps the build well within small containers (2 vCPU / 512 MB profile).
RUN mkdir -p nheqminer/build \
    && cd nheqminer/build \
    && cmake .. \
    && make -j2 \
    && strip nheqminer

# --- Runtime -----------------------------------------------------------------
FROM ubuntu:22.04

# The miner needs no privileges; run as an unprivileged user.
RUN useradd --create-home --shell /bin/sh miner

COPY --from=builder /build/nheqminer/build/nheqminer /usr/local/bin/nheqminer
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

USER miner
WORKDIR /home/miner

# Railway overrides these via project Variables. WALLET_ADDRESS and POOL_URL are
# required and must be set there (start.sh refuses to start without them).
# Railway: set memory to 1 GB in Service → Settings → Resources.
ENV THREADS=1 \
    WORKER_NAME=worker

ENTRYPOINT ["/usr/local/bin/start.sh"]
