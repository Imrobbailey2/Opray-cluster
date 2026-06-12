#!/bin/bash
export RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO=0
# Ray Head Node Startup Script
# Head Node - Primary GPU Worker

# Activate Ray venv
source ~/venvs/ray/bin/activate

# Get current LAN IP (mirrored networking mode)
LAN_IP=$(hostname -I | awk '{print $1}')
echo "Starting Ray head node on: $LAN_IP"

ray start --head \
  --disable-usage-stats \
  --disable-usage-stats \
  --node-ip-address=$LAN_IP \
  --port=6379 \
  --dashboard-host=0.0.0.0 \
  --dashboard-port=8265 \
  --ray-client-server-port=10001 \
  --node-manager-port=20001 \
  --object-manager-port=10002 \
  --min-worker-port=20002 \
  --max-worker-port=20100 \
  --num-gpus=1 \
  --verbose

echo ""
echo "Ray Dashboard: http://$LAN_IP:8265"
echo "Ray Address for workers: $LAN_IP:6379"
