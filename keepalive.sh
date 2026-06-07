#!/bin/bash
# keepalive.sh — Place on phone at ~/keepalive.sh
# Watches llama-server and restarts if it dies or stops responding
# Called from start-llama.sh after boot

INTERVAL=60
echo "$(date): keepalive started" >> /data/data/com.termux/files/home/watchdog.log

while true; do
    if ! pgrep -f "llama-server" > /dev/null 2>&1; then
        # llama-server not running at all
        echo "$(date): llama-server not running, restarting" >> /data/data/com.termux/files/home/watchdog.log
        bash /data/data/com.termux/files/home/watchdog.sh
    elif ! curl -s --connect-timeout 3 http://127.0.0.1:8081/health > /dev/null 2>&1; then
        # Process might be stuck
        echo "$(date): llama-server not responding, restarting" >> /data/data/com.termux/files/home/watchdog.log
        bash /data/data/com.termux/files/home/watchdog.sh
    fi
    sleep $INTERVAL
done
