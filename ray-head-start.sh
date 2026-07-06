#!/bin/bash
# ==============================================================
# Opray Cluster - Head Node Startup Script
# Run on firstfolk-v2 to start the Ray head node.
# ==============================================================

export RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO=0
export RAY_USAGE_STATS_ENABLED=0
export RAY_DISABLE_MEMORY_MONITOR=1

# Activate venv (firstfolk-v2 path)
source ~/ray-head/.venv/bin/activate

# Use Tailscale IP if available (permanent, survives DHCP changes)
# Falls back to route-based detection if Tailscale is not running
LAN_IP=$(tailscale ip -4 2>/dev/null || ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')
echo "Starting Ray head node on: $LAN_IP"

ray start --head \
  --node-ip-address=$LAN_IP \
  --port=6379 \
  --dashboard-host=0.0.0.0 \
  --dashboard-port=8265 \
  --ray-client-server-port=10001 \
  --node-manager-port=20001 \
  --object-manager-port=10002 \
  --min-worker-port=20002 \
  --max-worker-port=20100 \
  --disable-usage-stats \
  --system-config='{"memory_monitor_refresh_ms":0,"health_check_initial_delay_ms":5000,"health_check_period_ms":5000,"health_check_timeout_ms":30000,"health_check_failure_threshold":6}' \
  --verbose

echo ""
echo "Ray Dashboard: http://$LAN_IP:8265"
echo "Ray Address for workers: $LAN_IP:6379"

# Launch Prometheus with Ray-generated config
echo "Starting Prometheus..."
ray metrics launch-prometheus &
sleep 3

# Launch Grafana with Ray-generated config
echo "Starting Grafana..."
sudo grafana-server \
    --config /tmp/ray/session_latest/metrics/grafana/grafana.ini \
    --homepath /usr/share/grafana \
    web >> /tmp/grafana.log 2>&1 &

echo "Prometheus: http://$LAN_IP:9090"
echo "Grafana:    http://$LAN_IP:3000"
