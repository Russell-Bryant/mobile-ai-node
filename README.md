# Mobile AI Inference Node

Setup documentation for running llama.cpp on Android (Termux) as an AI inference backend for agent harnesses.

## What This Project Does

This repo turns an Android phone into a **local LLM inference node** — a failover AI backend that runs entirely on-device, no cloud required. It exposes an OpenAI-compatible API via `llama-server` that any agent harness can connect to.

**This is the inference layer.** By itself, the phone just serves completions. To make it useful you need two more pieces:

| Layer | What it does | Examples |
|-------|-------------|----------|
| **UI / Messaging** | Where you talk to the agent | Telegram, Discord, WhatsApp, Signal, Slack |
| **Agent Harness** | Orchestrates tools, memory, scheduling, multi-step reasoning | Hermes Agent, OpenClaw |
| **Inference** *(this repo)* | Runs the LLM, generates responses | llama.cpp on phone |

### UI / Messaging Platform

You need a messaging platform as the **entry point** for conversations. The harness connects to it as a bot:

- **Telegram** — Bot API via `python-telegram-bot` or grammY. Most popular for personal AI agents. Supports inline buttons, topics, groups.
- **Discord** — Bot API via `discord.py`. Good for multi-user servers, thread-based conversations.
- **WhatsApp** — Business API or Baileys-based bridges. Higher friction to set up but reaches the most users.
- **Signal** — `signal-cli` bridge. Best privacy, smallest ecosystem.
- **Slack** — Bot tokens + Socket Mode. Team-oriented.

The phone node doesn't connect to any of these directly — the **harness** does. The phone just serves completions over HTTP.

### Agent Harness

The harness is the **brain** that sits between the UI and the inference backend:

- **Hermes Agent** (this setup) — Open-source, self-hosted, tool-calling, cron jobs, session memory, multi-provider fallback. Connects to Telegram, Discord, WhatsApp, Signal, Slack, Matrix, and more. Config-driven via `~/.hermes/config.yaml`.
- **OpenClaw** — Another open-source agent framework with similar goals. Also supports multiple messaging backends and local inference.

Both expect an OpenAI-compatible `/v1/chat/completions` endpoint. That's what `llama-server` provides.

## Architecture

```
┌──────────────┐
│  Telegram /   │  ← You talk here
│  Discord /    │
│  WhatsApp     │
└──────┬───────┘
       │
┌──────▼───────┐
│  Agent        │  ← Hermes / OpenClaw
│  Harness      │     (VPS, tools, memory, scheduling)
└──────┬───────┘
       │  SSH tunnel (port 18081 → 8081)
┌──────▼───────┐
│  Phone        │  ← This repo
│  llama-server │     (Termux, CPU inference)
│  Qwen3-4B     │
└──────────────┘
```

**Data flow:** You send a message on Telegram → harness receives it → harness builds a prompt with tools/memory → sends to phone via SSH tunnel → llama.cpp generates a response → harness delivers it back to Telegram.

The phone is a **failover tier** — when your primary GPU workstation is offline, the harness routes inference to the phone automatically.

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
| `-c` | 40960 | Context window (model's training context). Do NOT set higher — llama.cpp caps to GGUF metadata. Set `context_length: 65536` in Hermes config.yaml to satisfy the 64K minimum. |
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
    # NOTE: -c 40960 is the model's training context. Hermes 64K minimum
    # is satisfied via context_length: 65536 in config.yaml, not here.
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
    context_length: 65536
```

Model options:
- **Qwen3-4B-Q4_K_M**: Fast, non-reasoning, best for agent tasks
- Other non-reasoning models in the 4B-8B range work well too

**Avoid thinking/reasoning models** — see warning above. They are 2-5x slower and unstable on mobile.

### Other Harnesses

The phone's `llama-server` exposes a standard OpenAI-compatible API. Any harness that supports custom OpenAI endpoints can use it — just point `base_url` at the SSH tunnel (e.g., `http://127.0.0.1:18081/v1`). The 64K context override described below is Hermes-specific; other harnesses may have different minimums or none at all.

### ⚠️ Hermes 64K Context Minimum (Hermes-Specific Requirement)

**This section only applies if you're using Hermes Agent as your harness.** Other harnesses (OpenClaw, etc.) have their own context requirements or none at all — check their docs.

Hermes Agent hardcodes a **minimum 64,000 token context window** (`MINIMUM_CONTEXT_LENGTH = 64_000` in `agent/model_metadata.py:133`). At startup, Hermes checks the model's context length and **refuses to load** anything below 64K:

```
ValueError: Model ... has a context window of 40,960 tokens, which is below
the minimum 64,000 required by Hermes Agent.
```

Qwen3-4B's GGUF reports `n_ctx_train: 40960` — below Hermes' floor. This is a **Hermes limitation**, not a llama.cpp or model limitation. The model can actually handle longer contexts via RoPE scaling, but Hermes doesn't care — it checks the GGUF metadata value at init and bails.

**The fix** is a config-level override in `~/.hermes/config.yaml`:

```yaml
providers:
  phone:
    context_length: 65536   # ← Hermes reads this FIRST, before querying the model
```

Hermes' context resolution order is:
1. **Config override** (`providers.phone.context_length`) ← this is what we set
2. Persistent cache
3. Model metadata from `/v1/models` or `/props`
4. Hardcoded defaults

By setting `context_length: 65536` in config, Hermes accepts the model at step 1 and never checks the GGUF's `n_ctx_train`. The actual llama.cpp server still allocates a 40960-token KV cache — that's fine for a mobile failover node doing lightweight tasks.

**Do NOT set `-c` above 40960 in llama.cpp** — the GGUF metadata caps it and llama.cpp will ignore the override. The config override is purely to satisfy Hermes' init check.

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
