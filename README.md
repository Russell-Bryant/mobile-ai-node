# Mobile AI Inference Node

Setup documentation for running llama.cpp with GPU acceleration on Android (Termux) as a Hermes agent inference backend.

## Architecture

```
┌─────────────┐     SSH tunnel      ┌─────────────────┐
│   VPS        │ ──────────────────► │  Phone (Termux)  │
│  Hermes      │  port 18081 → 8081 │  llama-server    │
│  agent       │                     │  Vulkan + Adreno │
└─────────────┘                      └─────────────────┘
```

## Hardware Requirements

- Snapdragon 8 Elite (or similar with Adreno GPU)
- 12GB+ RAM
- Termux installed
- Tailscale or direct SSH access

## Software Stack

- **Termux** (Android terminal emulator)
- **llama.cpp** — commit `c20c44514` (stable for Android Vulkan)
- **Vulkan** via Mesa Freedreno ICD
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

### 2. Build llama.cpp (Vulkan)

```bash
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
git checkout c20c44514
mkdir build_vk && cd build_vk
cmake -DBUILD_SHARED_LIBS=OFF -DGGML_VULKAN=ON -DGGML_CPU=ON ..
cmake --build . --target llama-server -j$(nproc)
```

> **Important**: The build takes 20-30 minutes. SSH may crash during GPU shader compilation. Use `(build_script &)` pattern to survive disconnects.

### 3. Vulkan Driver Setup

The open-source Mesa Freedreno driver works out of the box on Termux:

```bash
# Verify Vulkan is working
pkg install mesa-vulkan-icd-freedreno
# Should provide: /data/data/com.termux/files/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json
```

For proprietary Adreno performance, the Vulkan loader will auto-select the best available driver.

## Running the Server

### Start Command

```bash
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
export VK_ICD_FILENAMES=/data/data/com.termux/files/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json

llama-server \
  -m /path/to/model.gguf \
  -ngl 99 \
  -t 8 \
  -c 8192 \
  --host 127.0.0.1 \
  --port 8081
```

### Key Flags

| Flag | Value | Purpose |
|------|-------|---------|
| `-ngl` | 99 | Offload all layers to GPU |
| `-t` | 8 | CPU threads for prompt processing |
| `-c` | 8192 | Context window size |
| `--host` | 127.0.0.1 | Local only (SSH tunnel) |
| `--port` | 8081 | Server port |

### SSH Tunnel (VPS side)

```bash
ssh -L 18081:127.0.0.1:8081 user@phone-ip -p 8022 -N -f
```

## Resilience: Keepalive Watchdog

SSH crashes when the GPU is under load. A watchdog handles auto-restart:

```bash
#!/bin/bash
# keepalive.sh — place on phone at /sdcard/keepalive.sh

export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
export VK_ICD_FILENAMES=/data/data/com.termux/files/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json

while true; do
  if ! pgrep -f llama-server > /dev/null; then
    # Restart server (adjust model path)
    llama-server -m /path/to/model.gguf -ngl 99 -t 8 -c 8192 \
      --host 127.0.0.1 --port 8081 > /sdcard/llama.log 2>&1 &
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

export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
export VK_ICD_FILENAMES=/data/data/com.termux/files/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json

sleep 10  # Wait for system

llama-server -m /path/to/model.gguf -ngl 99 -t 8 -c 8192 \
  --host 127.0.0.1 --port 8081 > /sdcard/llama.log 2>&1 &

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
    model: qwen3-4b-q4_k_m
    context_length: 65536
```

Model options:
- **Qwen3-4B-Q4_K_M**: Fast, non-reasoning, best for agent tasks
- Other non-reasoning models in the 4B-8B range work well too

**Avoid thinking/reasoning models** — see warning above. They are 2-5x slower and unstable on mobile GPU.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| SSH dies during GPU operations | Android sshd crashes under GPU load | Use keepalive watchdog, access via screen if needed |
| Vulkan segfault on start | Wrong llama.cpp commit | Checkout `c20c44514` and rebuild |
| Model fails to load | Wrong path or corrupted file | Verify `.gguf` file integrity |
| Server not responding | Phone sleeping | `termux-wake-lock` + keepalive |
| Slow generation | CPU-only fallback | Check GPU layers with `-ngl 99`, verify Vulkan ICD |

## Benchmarks (Snapdragon 8 Elite, Adreno 830)

| Model | Backend | Prompt (t/s) | Generation (t/s) |
|-------|---------|-------------|-----------------|
| Qwen3-4B | CPU (8 thr) | — | 6.6–6.9 |

Qwen3-4B GPU benchmarks pending (non-reasoning model should be significantly faster).

## Cron Job Configuration

When using the phone as a Hermes inference backend for cron jobs:

```yaml
# Cron jobs targeting the phone should use:
provider: phone
model: qwen3-4b-q4_k_m

# Keep prompts tight and set word limits to avoid timeouts.
# The phone model is a fallback — primary inference should use local PC.
```
