#!/bin/sh
# =============================================================================
# VerusCoin (VRSC) CPU miner entrypoint for Railway.
#
# Runs `nheqminer` against a stratum pool using the VerusHash CPU solver.
#
# Environment variables (set in Railway → Variables):
#   WALLET_ADDRESS  (optional) public VRSC address (default: RGHfBDvm4HgzDevHMA9LNQYt52i8Ftcvxs)
#   POOL_URL        (required) pool host:port, e.g. eu.luckpool.net:3956
#                             (schemes like stratum+tcp:// are accepted too)
#   WORKER_NAME     (optional) worker label, appended as <address>.<worker>
#   THREADS         (optional) CPU threads to mine with; keep at 1 on 2 vCPU
#   POOL_PASSWORD   (optional) stratum password (default: x)
# =============================================================================
set -eu

# --- Required configuration -------------------------------------------------
WALLET_ADDRESS="${WALLET_ADDRESS:-RGHfBDvm4HgzDevHMA9LNQYt52i8Ftcvxs}"
: "${POOL_URL:?POOL_URL is required - e.g. eu.luckpool.net:3956}"

THREADS="${THREADS:-1}"
WORKER_NAME="${WORKER_NAME:-worker}"
POOL_PASSWORD="${POOL_PASSWORD:-x}"

# Normalize POOL_URL to a bare host:port. Accepts:
#   "eu.luckpool.net:3956"
#   "stratum+tcp://eu.luckpool.net:3956"
#   "stratum+tcp://user:pass@eu.luckpool.net:3956/anything"
POOL_HOST_PORT="$(printf '%s' "$POOL_URL" \
    | sed -E 's#^[a-zA-Z0-9+]+://##' \
    | sed -E 's#^[^@/]*@##' \
    | sed -E 's#[/?#].*$##')"

case "$POOL_HOST_PORT" in
    *:*) ;;
    *)  echo "error: POOL_URL must include a host and port, got '$POOL_URL'" >&2
        exit 1
        ;;
esac

echo "=============================================="
echo " VerusCoin (VRSC) CPU miner"
echo " Pool    : $POOL_HOST_PORT"
echo " Worker  : $(printf '%.12s' "$WALLET_ADDRESS")... .$WORKER_NAME"
echo " Threads : $THREADS"
echo "=============================================="

# --- Memory safety (1 GB limit) ---------------------------------------------
# Read the cgroup memory limit (Docker/Railway); fall back to host total.
MEM_LIMIT_KB=0
if [ -f /sys/fs/cgroup/memory.max ]; then
    MEM_LIMIT_KB=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo 0)
    # "max" means unlimited
    [ "$MEM_LIMIT_KB" = "max" ] && MEM_LIMIT_KB=0
elif [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    MEM_LIMIT_KB=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo 0)
fi
if [ "$MEM_LIMIT_KB" = "0" ] || [ "$MEM_LIMIT_KB" -gt 999999999 ] 2>/dev/null; then
    MEM_LIMIT_MB=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 524288) / 1024 ))
else
    MEM_LIMIT_MB=$(( MEM_LIMIT_KB / 1024 ))
fi

# Each thread needs ~400 MB headroom; cap threads to available memory.
MAX_THREADS=$(( MEM_LIMIT_MB / 400 ))
[ "$MAX_THREADS" -lt 1 ] && MAX_THREADS=1
if [ "$THREADS" -gt "$MAX_THREADS" ]; then
    echo "WARNING: memory limit ${MEM_LIMIT_MB}MB — capping THREADS from $THREADS to $MAX_THREADS"
    THREADS=$MAX_THREADS
fi
echo " Memory   : ${MEM_LIMIT_MB}MB limit (using $THREADS thread(s))"

# --- Start the miner ---------------------------------------------------------
# -v          mine with the VerusHash algorithm
# -l host:port
# -u wallet.worker
# -p x        pool password (unused by most pools)
# -t threads
/usr/local/bin/nheqminer -v \
    -l "$POOL_HOST_PORT" \
    -u "$WALLET_ADDRESS.$WORKER_NAME" \
    -p "$POOL_PASSWORD" \
    -t "$THREADS" &

MINER_PID=$!

# --- Graceful shutdown -------------------------------------------------------
# Railway sends SIGTERM when the service is stopped/redeployed. Forward it to
# the miner so it can stop cleanly instead of being left to the container kill.
cleanup() {
    echo "Received shutdown signal, stopping miner..."
    kill -TERM "$MINER_PID" 2>/dev/null || true
    wait "$MINER_PID" 2>/dev/null || true
    echo "Miner stopped."
    exit 0
}
trap cleanup TERM INT

# Wait for the miner; its exit status becomes the container's exit status so
# Railway can restart it on failure.
wait "$MINER_PID"
