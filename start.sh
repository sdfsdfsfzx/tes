#!/bin/sh
set -eu

# =============================================================================
# VerusCoin (VRSC) CPU miner
# Configuration is hardcoded - no Railway Variables required.
# =============================================================================

# --- Configuration -----------------------------------------------------------

WALLET_ADDRESS="RGHfBDvm4HgzDevHMA9LNQYt52i8Ftcvxs"
POOL_URL="eu.luckpool.net:3956"
WORKER_NAME="railway"
POOL_PASSWORD="x"
THREADS="1"

# --- Normalize POOL_URL ------------------------------------------------------

POOL_HOST_PORT="$(printf '%s' "$POOL_URL" \
    | sed -E 's#^[a-zA-Z0-9+]+://##' \
    | sed -E 's#^[^@/]*@##' \
    | sed -E 's#[/?#].*$##')"

case "$POOL_HOST_PORT" in
    *:*) ;;
    *)
        echo "ERROR: invalid pool address: $POOL_HOST_PORT" >&2
        exit 1
        ;;
esac

# --- Banner ------------------------------------------------------------------

echo "=============================================="
echo " VerusCoin (VRSC) CPU Miner"
echo "=============================================="
echo " Wallet  : $WALLET_ADDRESS"
echo " Pool    : $POOL_HOST_PORT"
echo " Worker  : $WORKER_NAME"
echo " Threads : $THREADS"
echo "=============================================="

# --- Detect memory limit -----------------------------------------------------

MEM_LIMIT_KB=0

if [ -f /sys/fs/cgroup/memory.max ]; then
    MEM_LIMIT_KB=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo 0)

    if [ "$MEM_LIMIT_KB" = "max" ]; then
        MEM_LIMIT_KB=0
    fi

elif [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    MEM_LIMIT_KB=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo 0)
fi

# --- Calculate memory in MB --------------------------------------------------

if [ "$MEM_LIMIT_KB" = "0" ] || [ "$MEM_LIMIT_KB" -gt 999999999 ] 2>/dev/null; then

    MEM_LIMIT_MB=$(
        awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 512
    )

else

    MEM_LIMIT_MB=$((MEM_LIMIT_KB / 1024))

fi

# --- Limit threads based on RAM ---------------------------------------------

MAX_THREADS=$((MEM_LIMIT_MB / 400))

if [ "$MAX_THREADS" -lt 1 ]; then
    MAX_THREADS=1
fi

if [ "$THREADS" -gt "$MAX_THREADS" ]; then
    echo "WARNING: ${MEM_LIMIT_MB}MB RAM detected."
    echo "Reducing threads from $THREADS to $MAX_THREADS."
    THREADS=$MAX_THREADS
fi

echo " Memory  : ${MEM_LIMIT_MB}MB"
echo " Threads : ${THREADS}"
echo "=============================================="

# --- Check miner -------------------------------------------------------------

if [ ! -x /usr/local/bin/nheqminer ]; then
    echo "ERROR: /usr/local/bin/nheqminer not found!"
    exit 1
fi

# --- Start miner -------------------------------------------------------------

echo "Starting nheqminer..."

exec /usr/local/bin/nheqminer \
    -v \
    -l "$POOL_HOST_PORT" \
    -u "$WALLET_ADDRESS.$WORKER_NAME" \
    -p "$POOL_PASSWORD" \
    -t "$THREADS"
