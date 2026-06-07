#!/bin/bash
# watchdog.sh — Place on phone at ~/watchdog.sh
# Restarts llama-server if it dies or stops responding
# Called by keepalive.sh when a problem is detected

LOG=/data/data/com.termux/files/home/watchdog.log
MODEL=/data/data/com.termux/files/home/models/qwen3-4b/Qwen3-4B-Q4_K_M.gguf

# Check if llama-server is already responding
if curl -s --connect-timeout 3 http://127.0.0.1:8081/health > /dev/null 2>&1; then
    exit 0  # All good
fi

# Process alive but not responding?
if pgrep -f llama-server > /dev/null 2>&1; then
    echo "$(date): Process alive but not responding, killing" >> "$LOG"
    pkill -9 -f llama-server 2>/dev/null
    sleep 2
fi

# Restart
echo "$(date): RESTARTING llama-server" >> "$LOG"

export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
screen -S llama -X quit 2>/dev/null
sleep 2

screen -dmS llama bash -c "export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib:\$LD_LIBRARY_PATH; /data/data/com.termux/files/usr/bin/llama-server --model $MODEL --port 8081 --threads 8 --ctx-size 40960 --host 0.0.0.0 --chat-template chatml --metrics --log-disable; exec bash"

# Verify
sleep 8
if curl -s --connect-timeout 5 http://127.0.0.1:8081/health > /dev/null 2>&1; then
    echo "$(date): Restart OK" >> "$LOG"
else
    echo "$(date): Restart FAILED" >> "$LOG"
fi
