# Ray Cluster — IF-CALS

Distributed GPU compute cluster for LLM inference, rendering, ML training,
and computational imaging.

## Cluster
- **Head Node:** IF-CALS-J3XGWM3 (W11/WSL2, RTX A4000 16GB) — `10.242.22.65`
- **Worker 1:** IF-CALS-94Q1LY3 (Dell Precision 3581, RTX A1000 6GB) — `10.136.213.46`

## Usage

### Head Node (run once per WSL2 session)
```bash
~/scripts/ray-head-start.sh

# 1. Provision (one-time per machine)
bash provision-ray-worker.sh [HEAD_IP]

# 2. Join cluster (each session)
~/scripts/ray-worker-start.sh
Dashboard
http://10.242.22.65:8265
Ray Version: 2.55.1 | Python: 3.12.13 | CUDA: 12.4
