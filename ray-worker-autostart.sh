#!/bin/bash
# ==============================================================
# Opray Cluster - Worker Auto-Start Script
# Runs at system boot via Windows Task Scheduler (SYSTEM account)
# No interactive input required.
# ==============================================================

export RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO=0
export RAY_USAGE_STATS_ENABLED=0
export RAY_DISABLE_MEMORY_MONITOR=1

LOG_FILE="/tmp/ray-autostart.log"
HEAD_IP="100.117.146.7"   # firstfolk-v2 Tailscale IP -- permanent

echo "$(date) -- Opray worker autostart beginning" >> "$LOG_FILE"

# Clear any stale pause flag from previous session
if [[ -f /tmp/ray-paused ]]; then
    echo "$(date) -- Stale pause flag found, clearing for boot startup" >> "$LOG_FILE"
    rm -f /tmp/ray-paused
fi

# Wait for Tailscale and head node (nc instead of ping -- Tailscale may block ICMP)
echo "$(date) -- Waiting for network and head node at $HEAD_IP:6379..." >> "$LOG_FILE"
NETWORK_READY=0
for i in $(seq 1 30); do
    if nc -z -w5 "$HEAD_IP" 6379 &>/dev/null; then
        echo "$(date) -- Network ready on attempt $i, head node reachable" >> "$LOG_FILE"
        NETWORK_READY=1
        break
    fi
    echo "$(date) -- Attempt $i/30: head node not reachable, retrying in 5s..." >> "$LOG_FILE"
    sleep 5
done

if [[ $NETWORK_READY -eq 0 ]]; then
    echo "$(date) -- FATAL: Head node unreachable after 30 attempts. Exiting." >> "$LOG_FILE"
    exit 1
fi

# Activate Ray venv
source ~/venvs/ray/bin/activate

# Stop any stale Ray processes
ray stop --force 2>/dev/null || true
sleep 2

# Detect worker Tailscale IP (preferred) with fallback to route-based detection
WORKER_IP=$(tailscale ip -4 2>/dev/null || ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')
echo "$(date) -- Worker IP: $WORKER_IP" >> "$LOG_FILE"
echo "$(date) -- Joining Ray cluster at $HEAD_IP:6379" >> "$LOG_FILE"

# Join the cluster
ray start \
  --address=$HEAD_IP:6379 \
  --node-ip-address=$WORKER_IP \
  --node-manager-port=20001 \
  --object-manager-port=10002 \
  --min-worker-port=20002 \
  --max-worker-port=20100 \
  --num-gpus=1 \
  --disable-usage-stats \
  --verbose >> "$LOG_FILE" 2>&1

echo "$(date) -- Ray worker start complete" >> "$LOG_FILE"
