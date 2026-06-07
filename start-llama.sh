#!/bin/bash
# ~/.termux/boot/start-llama.sh
# Auto-starts llama-server on phone boot via Termux:Boot

sleep 10  # Wait for system

MODEL=/data/data/com.termux/files/home/storage/shared/AI_Models/Qwen3-4B-Q4_K_M.gguf
BINARY=/data/data/com.termux/files/home/llama.cpp/build_cpu/bin/llama-server
LOG=/data/data/com.termux/files/home/llama.log

# NOTE: -c 40960 is the model's training context (n_ctx_train). Do NOT set
# higher — llama.cpp caps to GGUF metadata. Hermes requires 64K minimum;
# set context_length: 65536 in ~/.hermes/config.yaml to satisfy that check.
$BINARY -m $MODEL -ngl 0 -t 8 -c 40960 \
  --host 0.0.0.0 --port 8081 > $LOG 2>&1 &

sleep 5
# Start watchdog
bash /sdcard/keepalive.sh &
