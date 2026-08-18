# VerusCoin (VRSC) CPU Miner for Railway

A lightweight Docker container that mines VerusCoin using the official
[VerusCoin `nheqminer`](https://github.com/VerusCoin/nheqminer) binary, compiled
from source inside the image. Built to fit Railway's smallest profile
(**2 vCPU / 1 GB RAM**) and to start mining automatically on deploy.

The final image is a bare Ubuntu 22.04 runtime (~40 MB) carrying only the
stripped miner binary and the entrypoint.

## Quick deploy on Railway

1. **Push this repository to GitHub** (Railway deploys from a repo).
2. In Railway, click **New Project → Deploy from GitHub repo** and pick it.
   Railway auto-detects the `Dockerfile`; no build commands needed.
3. Open **Deploy Settings → Variables** and set (at minimum):

   | Variable          | Example value              | Required |
   |-------------------|----------------------------|----------|
   | `WALLET_ADDRESS`  | `RGHfBDvm4HgzDevHMA9LNQYt52i8Ftcvxs` | pre-set ✅ |
   | `POOL_URL`        | `eu.luckpool.net:3956`     | ✅ yes |
   | `WORKER_NAME`     | `railway`                  | optional |
   | `THREADS`         | `1`                        | optional |
   | `POOL_PASSWORD`   | `x`                        | optional |

4. **Set memory limit:** In Railway, go to your service → **Settings** → **Resources**
   and set the plan to **2 vCPU / 1 GB RAM**. The miner uses ~400 MB per thread,
   so 1 GB gives headroom for the OS and a single mining thread.
5. **Deploy.** The container builds the miner, then `start.sh` connects to your
   pool and starts hashing immediately.

## Environment variables

| Variable          | Default   | Description |
|-------------------|-----------|-------------|
| `WALLET_ADDRESS`  | `RGHfBDvm4HgzDevHMA9LNQYt52i8Ftcvxs` | Your public VRSC address (starts with `R`). Pre-set in code; override via Railway Variables if needed. |
| `POOL_URL`        | *(none)*  | Pool in `host:port` form. `stratum+tcp://` prefixes and `user:pass@` are stripped automatically. **Required.** |
| `WORKER_NAME`     | `worker`  | Worker label, appended as `<wallet>.<worker>`. |
| `THREADS`         | `1`       | CPU threads the miner uses. Keep at `1` on the 2 vCPU plan. |
| `POOL_PASSWORD`   | `x`       | Stratum password. Most pools ignore it. |

## Picking a pool

VerusHash (VRSC) pools, all reachable over standard stratum:

| Pool             | Address                          |
|------------------|----------------------------------|
| LuckPool         | `eu.luckpool.net:3956` (EU), `us.luckpool.net:3956` (US) |
| VerusPool.io     | `veruspool.io:9999`              |
| R9Pools          | `vrsc.r-pools.net:3956`          |
| Zergpool         | `verushash.asia.mine.zergpool.com:4569` |

Set `POOL_URL` to one of these. For a free wallet address, install the official
Verus Desktop wallet or create a lightweight wallet at <https://verus.io>.
**Always verify a pool's current endpoint and minimum payout on its own site.**

## Resource tuning for 2 vCPU / 1 GB RAM

- **`THREADS=1`** is the default and the right choice here. Each VerusHash CPU
  thread buffers ~400 MB of scratch memory in the miner, so a second thread
  would push a 1 GB container toward OOM. `nheqminer` is explicitly told to
  run with `-t 1`, so **only 1 vCPU is ever used**.
- On Railway you can change the service to 2 vCPU; keep `THREADS=1` regardless.
- VerusHash needs the CPU to support **AES-NI + AVX + PCLMUL** instructions.
  Railway's Intel Xeon instances support them (the miner logs
  `Using AES, AVX, and PCLMUL: YES`). If your runtime lacks them, hashing will
  be slow and you'll see `NO` in that line.
- Expect roughly **1.5–2.5 MH/s** per thread on modern Xeon cores — enough for
  low/small-pool luck, not competitive for high-hashrate pools. This is a
  hobbyist/learning setup, not a profit rig.
- `start.sh` reads the container's cgroup memory limit (Docker / Railway) and
  automatically caps `THREADS` if memory is too low. You'll see a warning like
  `WARNING: memory limit 1024MB — capping THREADS from 2 to 1`.

## Graceful shutdown

Railway sends `SIGTERM` on stop/redeploy. `start.sh` traps it and forwards
`SIGTERM` to the miner, so the process exits cleanly instead of being hard-killed.
If the miner crashes, `start.sh` exits with its status and Railway restarts the
container.

## Building locally

```bash
# Build the image:
docker build -t verus-miner .

# Run with 1 GB memory limit:
docker run --rm --memory=1g \
  -e POOL_URL=eu.luckpool.net:3956 \
  -e WORKER_NAME=test \
  verus-miner

# Or override the wallet address:
docker run --rm --memory=1g \
  -e WALLET_ADDRESS=RGHfBDvm4HgzDevHMA9LNQYt52i8Ftcvxs \
  -e POOL_URL=eu.luckpool.net:3956 \
  verus-miner
```

## How the build works

- **Source:** `VerusCoin/nheqminer` pinned to commit
  `0b46244021a83a3adba6648e21cc11ad0aa90ee5`.
- **Solver:** only `USE_CPU_VERUSHASH` is compiled in (the repo default) — no
  CUDA, no Xenoncat/fasm, no OpenSSL.
- **Compatibility fix:** upstream targets Boost ~1.65; modern GCC (≥8, e.g.
  Ubuntu 22.04's GCC 11) rejects the `#pragma pack(1)` + `aligned(64)`
  combination in `blake2/blake2.h`. `patches/blake2-modern-gcc.patch` restores
  the pack regions so only the wire-format param structs are packed and drops
  the state structs' alignment to 8 (their sizes are 192/200 bytes, not
  multiples of 64). This is applied during the image build.
- **Boost is statically linked**, so the runtime stage ships no boost packages —
  `ldd` shows only `libstdc++`, `libgcc_s`, `libm`, `libc`.
- **Multi-stage:** builder compiles with `-j2` (safe in small containers); the
  final image copies only the stripped binary + `start.sh`.
- Runs as an unprivileged `miner` user.

## Files

```
Dockerfile                      multi-stage build (builder + runtime)
start.sh                        entrypoint: config, launch, graceful shutdown
patches/blake2-modern-gcc.patch modern-GCC fix for upstream blake2.h
railway.toml                    Railway build/deploy configuration
README.md                       this file
```

## Troubleshooting

- **`WALLET_ADDRESS is required`** on boot → variable not set; add it in
  Railway Variables and redeploy.
- **`POOL_URL must include a host and port`** → set `POOL_URL` to `host:port`,
  e.g. `eu.luckpool.net:3956`.
- **Connects then disconnects / `stratum_recv_line failed`** → pool blocked the
  worker or needs `-u` format `<wallet>.<worker>` (already the case here). Check
  the wallet address spelling and the pool's `POOL_URL` port.
- **High memory / OOM** → you raised `THREADS` above 1, or Railway's memory
  limit is too low. Set `THREADS=1` and ensure the service plan has at least
  1 GB RAM. `start.sh` auto-caps threads based on the cgroup memory limit.
- **Very low hashrate** → runtime CPU lacks AES-NI/AVX/PCLMUL, or Railway gave
  you a heavily shared core. Nothing to fix in the container.
- **Rebuild from scratch** → the `builder` stage is cached; edit the pinned
  `NHEQMINER_REF` or clear Railway's build cache to force a clean build.

## Disclaimer

Mining VerusHash on a 2-vCPU container is intended for learning and testing.
Rewards are negligible on shared/hosted CPU and electricity/hosting usually
cost more than the VRSC mined. Do not deploy against a pool you don't own or
without a wallet address you control.
