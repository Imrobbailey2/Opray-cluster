#!/bin/bash
export RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO=0
# Ray Worker Node Startup Script

source ~/venvs/ray/bin/activate

HEAD_IP="${RAY_HEAD_IP:?Error: set RAY_HEAD_IP first. Example: RAY_HEAD_IP=x.x.x.x ~/scripts/ray-worker-start.sh}"
WORKER_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')

echo "Joining Ray cluster at: $HEAD_IP:6379"
echo "Worker IP: $WORKER_IP"

ray stop --force 2>/dev/null || true
sleep 2

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
