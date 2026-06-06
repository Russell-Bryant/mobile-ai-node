#!/bin/bash
# keepalive.sh — Watchdog for llama-server on Android Termux
# Place at /sdcard/keepalive.sh on the phone
#
# Checks every 60 seconds if llama-server is running.
# Restarts it if dead. Logs to /sdcard/keepalive.log.

export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
export VK_ICD_FILENAMES=/data/data/com.termux/files/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json

LLAMA_SERVER="/data/data/com.termux/files/home/llama.cpp/build_vk/bin/llama-server"
MODEL="/path/to/your/model.gguf"

if [ ! -f "$MODEL" ]; then
  echo "$(date): Model not found: $MODEL" >> /sdcard/keepalive.log
  exit 1
fi
LOG="/sdcard/llama.log"

while true; do
  if ! pgrep -f llama-server > /dev/null 2>&1; then
    echo "$(date): Server dead, restarting..." >> /sdcard/keepalive.log
    cd /data/data/com.termux/files/home
    $LLAMA_SERVER \
      -m "$MODEL" \
      -ngl 99 \
      -t 8 \
      -c 8192 \
      --host 127.0.0.1 \
      --port 8081 > "$LOG" 2>&1 &
    sleep 5
  fi
  sleep 60
done
