#!/bin/bash
# ==============================================================
# Opray Cluster - Worker Auto-Start Script
# Runs at system boot via Windows Task Scheduler (SYSTEM account)
# No interactive input required.
# Update HEAD_IP below if the head node IP changes.
# ==============================================================

export RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO=0

LOG_FILE="/tmp/ray-autostart.log"
HEAD_IP="10.242.22.65"   # <-- Update if head node IP changes

echo "$(date) -- Opray worker autostart beginning" >> "$LOG_FILE"

# Clear any stale pause flag from previous session
if [[ -f /tmp/ray-paused ]]; then
    echo "$(date) -- Stale pause flag found, clearing for boot startup" >> "$LOG_FILE"
    rm -f /tmp/ray-paused
fi

# Wait for network and head node
echo "$(date) -- Waiting for network and head node..." >> "$LOG_FILE"
NETWORK_READY=0
for i in $(seq 1 30); do
    if ping -c 1 -W 2 "$HEAD_IP" &>/dev/null; then
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

# Detect worker IP
WORKER_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')
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
