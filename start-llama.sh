#!/bin/bash
# ~/.termux/boot/start-llama.sh
# Auto-starts llama-server on phone boot via Termux:Boot
# Uses screen so it survives Termux background kills

export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib

# Prevent Android from killing Termux
termux-wake-lock

# Wait for system to settle
sleep 15

MODEL=/data/data/com.termux/files/home/models/qwen3-4b/Qwen3-4B-Q4_K_M.gguf

# Kill any existing instances
pkill -9 -f llama-server 2>/dev/null
pkill -f keepalive.sh 2>/dev/null
screen -S llama -X quit 2>/dev/null
sleep 2

# Start llama-server in screen session
screen -dmS llama bash -c "export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib:\$LD_LIBRARY_PATH; /data/data/com.termux/files/usr/bin/llama-server --model $MODEL --port 8081 --threads 8 --ctx-size 40960 --host 0.0.0.0 --chat-template chatml --metrics --log-disable; exec bash"

echo "$(date): llama-server started" >> /data/data/com.termux/files/home/boot.log

# Start keepalive watchdog in background
sleep 5
nohup bash /data/data/com.termux/files/home/keepalive.sh >> /data/data/com.termux/files/home/watchdog.log 2>&1 &

echo "$(date): keepalive started" >> /data/data/com.termux/files/home/boot.log
