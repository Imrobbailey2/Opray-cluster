#!/bin/bash
export RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO=0
export RAY_memory_monitor_refresh_ms=0
# Ray Worker Node Startup Script
# Auto-provisioned Fri Jun 12 11:42:12 EDT 2026
# GPU: NVIDIA RTX A4000

source /home/robbailey/venvs/ray/bin/activate

HEAD_IP="${RAY_HEAD_IP:?Error: set RAY_HEAD_IP first. Example: RAY_HEAD_IP=x.x.x.x ~/scripts/ray-worker-start.sh}"
WORKER_IP=$(ip route get 8.8.8.8 2>/dev/null | awk "{print $7; exit}")

echo "Joining Ray cluster at: $HEAD_IP:6379"
echo "Worker IP: $WORKER_IP"

ray start \
  --address=$HEAD_IP:6379 \
  --node-ip-address=$WORKER_IP \
  --node-manager-port=20001 \
  --object-manager-port=10002 \
  --min-worker-port=20002 \
  --max-worker-port=20100 \
  --num-gpus=1 \
  --disable-usage-stats \
  --verbose
