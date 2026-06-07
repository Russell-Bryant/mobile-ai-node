#!/bin/bash
# phone-tunnel-keepalive.sh — Ensure SSH tunnel to phone llama-server is always up
# Place on VPS at ~/scripts/phone-tunnel-keepalive.sh
# Called by cron every 5 minutes

LOCAL_PORT=18081

# Check if tunnel is already listening and working
if ss -tlnp | grep -q ":${LOCAL_PORT}"; then
    if curl -s --connect-timeout 3 http://127.0.0.1:${LOCAL_PORT}/health >/dev/null 2>&1; then
        exit 0  # Tunnel is healthy
    fi
fi

# Tunnel is down or unhealthy — restart it
echo "[$(date)] Tunnel down, restarting..." >> /tmp/phone-tunnel.log

# Kill any stale SSH tunnel processes
pkill -f "ssh.*${LOCAL_PORT}:127.0.0.1:8081" 2>/dev/null
sleep 2

# Start new tunnel with keepalive options
ssh -i /home/russell/.ssh/id_ed25519 \
    -o StrictHostKeyChecking=no \
    -o BatchMode=yes \
    -o ServerAliveInterval=20 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -o ConnectTimeout=15 \
    -o TCPKeepAlive=yes \
    -L ${LOCAL_PORT}:127.0.0.1:8081 \
    -p 8022 \
    -N \
    100.96.22.12 &

sleep 5

# Verify
if curl -s --connect-timeout 5 http://127.0.0.1:${LOCAL_PORT}/health >/dev/null 2>&1; then
    echo "[$(date)] Tunnel restarted successfully" >> /tmp/phone-tunnel.log
else
    echo "[$(date)] Tunnel restart FAILED" >> /tmp/phone-tunnel.log
fi
