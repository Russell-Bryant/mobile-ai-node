# Mobile AI Inference Node

Setup documentation for running llama.cpp on Android (Termux) as a Hermes agent inference backend.

## Architecture

```
┌─────────────┐     SSH tunnel      ┌─────────────────────────────┐
│   VPS        │ ──────────────────► │  Phone (Termux)              │
│  Hermes      │  port 18081 → 8081 │  ┌─────────────────────────┐ │
│  agent       │                     │  │ screen: llama           │ │
│              │                     │  │  └─ llama-server :8081  │ │
│              │                     │  │ keepalive.sh (60s loop) │ │
│              │                     │  │ watchdog.sh (restart)   │ │
│              │                     │  └─────────────────────────┘ │
│              │                     │  termux-wake-lock active     │
│              │                     │  Termux:Boot registered      │
└─────────────┘                      └─────────────────────────────┘

Resilience layers:
  Phone boot ──► Termux:Boot ──► start-llama.sh ──► screen + keepalive
  llama dies  ──► keepalive (60s) ──► watchdog.sh ──► restart in screen
  tunnel drops ──► VPS cron (5min) ──► phone-tunnel-keepalive.sh ──► reconnect
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

## Resilience: Three-Layer Watchdog

### Layer 1: Boot Auto-Start (`start-llama.sh`)

Runs via Termux:Boot on phone startup. Acquires wake lock, kills stale instances, starts llama-server in a `screen` session, and launches the keepalive loop.

```bash
# ~/.termux/boot/start-llama.sh
termux-wake-lock
screen -dmS llama bash -c "llama-server --model ... --port 8081 ..."
nohup bash ~/keepalive.sh &
```

### Layer 2: Keepalive Loop (`keepalive.sh`)

Runs continuously on the phone. Every 60 seconds, checks if llama-server is alive and responding. Triggers the watchdog if not.

```bash
# ~/keepalive.sh — runs in background
while true; do
    if ! pgrep -f "llama-server" || ! curl -s http://127.0.0.1:8081/health; then
        bash ~/watchdog.sh
    fi
    sleep 60
done
```

### Layer 3: Watchdog (`watchdog.sh`)

Kills unresponsive llama-server processes and restarts in screen. Verifies the restart succeeded.

```bash
# ~/watchdog.sh — called by keepalive
pkill -9 -f llama-server
screen -dmS llama bash -c "llama-server ..."
# verify after 8s
```

### Layer 4: VPS Tunnel Keepalive (`vps-tunnel-keepalive.sh`)

Runs on the VPS via cron every 5 minutes. Checks if the SSH tunnel to the phone is healthy. Reconnects if down.

```bash
# Crontab (VPS):
*/5 * * * * /home/russell/scripts/phone-tunnel-keepalive.sh >/dev/null 2>&1
```

SSH options used: `ServerAliveInterval=20`, `ServerAliveCountMax=3`, `TCPKeepAlive=yes`, `ExitOnForwardFailure=yes`.

## ⚠️ Thinking/Reasoning Models — Not Advised

Thinking models (e.g. Nemotron, DeepSeek-R1, QwQ) generate internal reasoning tokens before producing a final response. On mobile GPU inference this causes:

- **2-5x slower generation** — thinking tokens consume context and GPU cycles
- **Context window exhaustion** — reasoning chains eat into limited mobile context
- **Unpredictable latency** — thinking depth varies per query, making response times inconsistent
- **Higher crash risk** — longer GPU workloads increase chance of SSH/sshd failure

**Use non-reasoning models only.** Qwen3-4B is the recommended choice — fast, capable, and designed for direct response generation.

## ✅ Capabilities & Limitations

This node uses a **4B parameter model with 40K context** on mobile hardware. That defines hard boundaries on what it can and cannot do. Don't fight them.

### What It Does Well

- **Short, focused Q&A** — factual lookups, definitions, quick explanations
- **Simple text transformations** — formatting, templating, light editing
- **Structured data tasks** — JSON parsing, extracting fields, simple filtering
- **Smart home control** — intent parsing for Home Assistant commands
- **Short summaries** — condensing a single document or thread
- **Bounded cron jobs** — health checks, file watchers, greeting messages
- **Script-only (`no_agent`) cron jobs** — the ideal use case; the node runs a script and delivers output

### What It Cannot Do

- **Multi-session analysis** — session_search + read + synthesize across multiple sessions (context fills fast; 93-minute truncation failure, June 2026)
- **Complex multi-tool workflows** — long chains of tool calls that accumulate context
- **Large document processing** — reviewing 100+ page decks or extracting from large codebases
- **Deep reasoning tasks** — architectural analysis, strategic planning, nuanced debugging
- **Code generation at scale** — small functions yes, full refactors no
- **Tasks triggering context compaction** — when Hermes compacts context mid-task on this node, quality drops sharply and outputs truncate

### Golden Rules

1. **Single task per request.** Don't ask it to research, analyze, and write in one go.
2. **Under 200 words output** for reliable completion. Long outputs = truncation risk.
3. **No recursive self-reference.** The node cannot analyze its own past sessions meaningfully.
4. **Not a primary device.** This is a fallback/edge node. Primary inference = LM Studio (RTX 3090, 27B+ models) or OpenRouter.
5. **`no_agent=True` cron jobs are the sweet spot.** Script delivers output directly — no LLM context needed.

### Verdict

**Good for:** always-on lightweight inference, emergency fallback when PC + cloud are down, `no_agent` script runners.

**Not a replacement for:** desktop GPUs, cloud models, or any task requiring deep reasoning over large context. Attempting this will waste time (see: 93-minute truncation failure).

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

### 3. Install Scripts

Copy the three resilience scripts to the phone:

```bash
# On phone:
cp start-llama.sh ~/.termux/boot/start-llama.sh
cp keepalive.sh ~/keepalive.sh
cp watchdog.sh ~/watchdog.sh
chmod +x ~/.termux/boot/start-llama.sh ~/keepalive.sh ~/watchdog.sh
```

### 4. Android Settings (Required)

- **Disable battery optimization** for Termux (Android Settings → Apps → Termux → Battery)
- **Enable Termux:Boot** app and run it at least once
- **Keep phone plugged in** for reliable operation

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
ssh -L 18081:127.0.0.1:8081 -p 8022 -N -f 100.96.22.12
```

For production, use the `vps-tunnel-keepalive.sh` cron job instead of a manual tunnel.

## Hermes Provider Configuration

```yaml
# ~/.hermes/config.yaml
model:
  context_length: 65536
  model: Qwen3-4B-Q4_K_M.gguf
  provider: phone

providers:
  phone:
    api_key: phone-local
    base_url: http://127.0.0.1:18081/v1
    context_length: 65536
    model: Qwen3-4B-Q4_K_M.gguf
```

**Note on context_length:** The model's actual training context is 40960. Hermes requires `context_length >= 65536` to pass its minimum check. Set `context_length: 65536` in the top-level `model:` section and in `providers.phone:`, and set `enforce_min_context: false` in the `agent:` section. The actual llama.cpp server will handle up to 40960.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| SSH dies during heavy operations | Android sshd crashes under sustained load | Use `screen` to access phone directly, check watchdog logs |
| Model fails to load | Wrong path or corrupted file | Verify `.gguf` file integrity, check `watchdog.log` |
| Server not responding | Phone sleeping | `termux-wake-lock` + disable battery optimization |
| Slow generation | Too few CPU threads | Use `-t 8` for 8-core phones |
| Context errors | Context exceeds model training limit | Cap at model's training context (40960 for Qwen3-4B) |
| Tunnel drops | Phone went to sleep / network change | VPS cron reconnects within 5 min; check `phone-tunnel.log` |
| "context not big enough" | Hermes enforce_min_context check | Set `enforce_min_context: false` in config, use `context_length: 65536` |

## Benchmarks (Snapdragon 8 Elite, 22GB RAM)

| Model | Backend | Avg Generation (t/s) | Notes |
|-------|---------|---------------------|-------|
| Qwen3-4B-Q4_K_M | CPU (8 threads) | **15.4** | Fastest config for this model |
| Qwen3-4B-Q4_K_M | GPU (Vulkan, ngl=99) | **8.7** | 77% slower than CPU |

**Why CPU is faster for Qwen3-4B:** The model is small enough (4B params, 2.5GB) that the CPU handles it efficiently. GPU overhead (Vulkan driver, memory transfers) actually slows things down. GPU only wins on larger models (13B+) where parallelization outweighs overhead.

**Recommendation:** Use CPU-only (`-ngl 0 -t 8`) for Qwen3-4B and similar small models.

## Cron Job Configuration

**Ideal use case: `no_agent=True` script-only jobs.** The node runs a script and delivers stdout — no LLM context consumed, no truncation risk.

```yaml
# Good — script-only, no LLM
no_agent: true
script: ~/.hermes/scripts/health-check.py
```

For LLM-driven cron jobs, keep them **small and bounded**:

```yaml
# OK — short prompt, small output
enabled_toolsets: ["terminal", "file"]
prompt: "Check disk usage. Report in under 100 words."
model:
  model: qwen3-4b-q4_k_m

# BAD — will likely truncate, 40K context not enough
prompt: "Search all recent sessions, read each one, synthesize a comprehensive status report, write to Obsidian, and sync"
```

**Rule of thumb:** if the job needs more than 2-3 tool calls or more than ~200 words of output, run it on LM Studio (27B) or OpenRouter instead.

## File Reference

| File | Location | Purpose |
|------|----------|---------|
| `start-llama.sh` | Phone: `~/.termux/boot/` | Boot auto-start (wake lock + screen + keepalive) |
| `keepalive.sh` | Phone: `~/` | 60s health check loop |
| `watchdog.sh` | Phone: `~/` | Restart llama-server if dead/unresponsive |
| `vps-tunnel-keepalive.sh` | VPS: `~/scripts/` | Reconnect SSH tunnel if dropped |
| `build.sh` | Phone: `llama.cpp/` | Build llama.cpp from source |
