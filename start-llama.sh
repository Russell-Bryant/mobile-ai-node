#!/data/data/com.termux/files/usr/bin/bash
# start-llama.sh — Boot auto-start for llama-server
# Place at ~/.termux/boot/start-llama.sh on the phone
#
# Requires: Termux:Boot app installed and run at least once
# Requires: termux-wake-lock (run manually once)

export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
export VK_ICD_FILENAMES=/data/data/com.termux/files/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json

# Wait for system to settle after boot
sleep 10

# Auto-select model
MODEL="/path/to/qwen3-4b-q4_k_m.gguf"

if [ ! -f "$MODEL" ]; then
  echo "Model not found: $MODEL" > /sdcard/llama_error.log
  exit 1
fi

LLAMA_SERVER="/data/data/com.termux/files/home/llama.cpp/build_vk/bin/llama-server"

# Start llama-server
cd /data/data/com.termux/files/home
nohup $LLAMA_SERVER \
  -m "$MODEL" \
  -ngl 99 \
  -t 8 \
  -c 8192 \
  --host 127.0.0.1 \
  --port 8081 > /sdcard/llama.log 2>&1 &

# Start watchdog
sleep 5
nohup /data/data/com.termux/files/usr/bin/bash /sdcard/keepalive.sh > /dev/null 2>&1 &
