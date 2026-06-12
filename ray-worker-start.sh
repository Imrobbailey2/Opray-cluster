#!/bin/bash
export RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO=0
# Ray Worker Node Startup Script
# Auto-provisioned Fri Jun 12 11:42:12 EDT 2026
# GPU: NVIDIA RTX A4000

source /home/robbailey/venvs/ray/bin/activate

HEAD_IP="10.242.22.65"
WORKER_IP="10.242.22.65"

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
