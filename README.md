# Mobile AI Inference Node

Setup documentation for running llama.cpp on Android (Termux) as a Hermes agent inference backend.

## Architecture

```
┌─────────────┐     SSH tunnel      ┌─────────────────┐
│   VPS        │ ──────────────────► │  Phone (Termux)  │
│  Hermes      │  port 18081 → 8081 │  llama-server    │
│  agent       │                     │  CPU (8 threads) │
└─────────────┘                      └─────────────────┘
```

## Hardware Requirements

- Snapdragon 8 Elite (or similar)
- 12GB+ RAM
- Termux installed
- Tailscale or direct SSH access

## Software Stack

- **Termux** (Android terminal emulator)
- **llama.cpp** — commit `c20c44514` (stable for Android)
- **CPU-only inference** — GPU (Vulkan) is slower for small models (see benchmarks)
- **Model**: Qwen3-4B-Q4_K_M (recommended)

## ⚠️ Thinking/Reasoning Models — Not Advised

Thinking models (e.g. Nemotron, DeepSeek-R1, QwQ) generate internal reasoning tokens before producing a final response. On mobile GPU inference this causes:

- **2-5x slower generation** — thinking tokens consume context and GPU cycles
- **Context window exhaustion** — reasoning chains eat into limited mobile context
- **Unpredictable latency** — thinking depth varies per query, making response times inconsistent
- **Higher crash risk** — longer GPU workloads increase chance of SSH/sshd failure

**Use non-reasoning models only.** Qwen3-4B is the recommended choice — fast, capable, and designed for direct response generation.

## Why This Commit

Later commits (`b36eefc1b+`) break Android Vulkan with segfaults during shader compilation. Commit `c20c44514` (May 2026) is the last known stable version for Adreno GPUs.

## Installation

### 1. Termux Setup

```bash
pkg update && pkg upgrade
pkg install git cmake build-essential vulkan-loader-android
pkg install screen curl python
termux-wake-lock
```

### 2. Build llama.cpp (CPU)

```bash
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
git checkout c20c44514
mkdir build_cpu && cd build_cpu
cmake -DBUILD_SHARED_LIBS=OFF ..
cmake --build . --target llama-server -j$(nproc)
```

Build takes 10-15 minutes. The CPU build is simpler and faster than GPU.

## Running the Server

### Start Command

```bash
llama-server \
  -m /path/to/model.gguf \
  -ngl 0 \
  -t 8 \
  -c 40960 \
  --host 0.0.0.0 \
  --port 8081
```

### Key Flags

| Flag | Value | Purpose |
|------|-------|---------|
| `-ngl` | 0 | CPU-only (GPU is slower for small models) |
| `-t` | 8 | CPU threads |
| `-c` | 40960 | Context window (capped by model training context) |
| `--host` | 0.0.0.0 | Allow SSH tunnel connections |
| `--port` | 8081 | Server port |

### SSH Tunnel (VPS side)

```bash
ssh -L 18081:127.0.0.1:8081 user@phone-ip -p 8022 -N -f
```

## Resilience: Keepalive Watchdog

```bash
#!/bin/bash
# keepalive.sh — place on phone

MODEL=/path/to/model.gguf
BINARY=llama.cpp/build_cpu/bin/llama-server

while true; do
  if ! pgrep -f llama-server > /dev/null; then
    $BINARY -m $MODEL -ngl 0 -t 8 -c 40960 \
      --host 0.0.0.0 --port 8081 > llama.log 2>&1 &
    sleep 5
  fi
  sleep 60
done
```

Check every 60 seconds. If server is dead, restart it.

## Resilience: Boot Auto-Start

```bash
#!/data/data/com.termux/files/usr/bin/bash
# ~/.termux/boot/start-llama.sh

sleep 10  # Wait for system

llama-server -m /path/to/model.gguf -ngl 0 -t 8 -c 40960 \
  --host 0.0.0.0 --port 8081 > llama.log 2>&1 &

sleep 5
# Start watchdog
bash /sdcard/keepalive.sh &
```

Requires Termux:Boot app to be installed and run at least once.

## Resilience: Wake Lock

```bash
termux-wake-lock
```

Prevents Android from killing Termux during sleep/screen-off.

## Background Process Trick

SSH on Android kills child processes when the session ends. To run long operations:

```bash
# WRONG — dies when SSH disconnects
nohup long_command &

# RIGHT — subshell detaches from SSH session
(long_command &)
```

The subshell pattern survives SSH disconnects because the parent exits immediately.

## Hermes Provider Configuration

```yaml
# ~/.hermes/config.yaml
providers:
  phone:
    base_url: http://127.0.0.1:18081/v1
    model: Qwen3-4B-Q4_K_M.gguf
    context_length: 40960
```

Model options:
- **Qwen3-4B-Q4_K_M**: Fast, non-reasoning, best for agent tasks
- Other non-reasoning models in the 4B-8B range work well too

**Avoid thinking/reasoning models** — see warning above. They are 2-5x slower and unstable on mobile.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| SSH dies during heavy operations | Android sshd crashes under sustained load | Use keepalive watchdog, access via screen if needed |
| Model fails to load | Wrong path or corrupted file | Verify `.gguf` file integrity |
| Server not responding | Phone sleeping | `termux-wake-lock` + keepalive |
| Slow generation | Too few CPU threads | Use `-t 8` for 8-core phones |
| Context errors | Context exceeds model training limit | Cap at model's training context (40960 for Qwen3-4B) |

## Benchmarks (Snapdragon 8 Elite, 22GB RAM)

| Model | Backend | Avg Generation (t/s) | Notes |
|-------|---------|---------------------|-------|
| Qwen3-4B-Q4_K_M | CPU (8 threads) | **15.4** | Fastest config for this model |
| Qwen3-4B-Q4_K_M | GPU (Vulkan, ngl=99) | **8.7** | 77% slower than CPU |

**Why CPU is faster for Qwen3-4B:** The model is small enough (4B params, 2.5GB) that the CPU handles it efficiently. GPU overhead (Vulkan driver, memory transfers) actually slows things down. GPU only wins on larger models (13B+) where parallelization outweighs overhead.

**Recommendation:** Use CPU-only (`-ngl 0 -t 8`) for Qwen3-4B and similar small models.

## Cron Job Configuration

When using the phone as a Hermes inference backend for cron jobs:

```yaml
# Cron jobs targeting the phone should use:
provider: phone
model: qwen3-4b-q4_k_m

# Keep prompts tight and set word limits to avoid timeouts.
# The phone model is a fallback — primary inference should use local PC.
```
