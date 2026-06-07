#!/bin/bash
# keepalive.sh — place on phone at /sdcard/keepalive.sh
# Watches llama-server and restarts if it dies

MODEL=/data/data/com.termux/files/home/storage/shared/AI_Models/Qwen3-4B-Q4_K_M.gguf
BINARY=/data/data/com.termux/files/home/llama.cpp/build_cpu/bin/llama-server
LOG=/data/data/com.termux/files/home/llama.log

while true; do
  if ! pgrep -f llama-server > /dev/null 2>&1; then
    echo "$(date): Server dead, restarting..." >> /data/data/com.termux/files/home/keepalive.log
    cd /data/data/com.termux/files/home
    $BINARY -m $MODEL -ngl 0 -t 8 -c 40960 \
      --host 0.0.0.0 --port 8081 > $LOG 2>&1 &
    sleep 5
  fi
  sleep 60
done
