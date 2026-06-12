cat > ~/ray-cluster/README.md << 'READMEOF'
# Ray Cluster

Distributed GPU compute cluster for LLM inference, rendering, ML training,
and computational imaging.

## Cluster Nodes

| Role | GPU | VRAM |
|---|---|---|
| Head Node + Primary Worker | NVIDIA RTX A4000 | 16GB |
| Worker 1 | NVIDIA RTX A1000 | 6GB |

## Requirements

- Windows 11 with WSL2 (Ubuntu 24.04+)
- NVIDIA GPU with CUDA 12.4 compatible driver (610.x or newer recommended)
- Python 3.12.13 (installed automatically by provisioning script)
- Machines on the same network segment (or routable between segments)

## Setup

### Head Node (first-time setup)

```bash
bash provision-ray-worker.sh <HEAD_NODE_IP>

##Head Node (each WSL2 session)
source ~/venvs/ray/bin/activate
~/scripts/ray-head-start.sh

Provision a New Worker (one-time per machine)
# Clone this repo on the new worker machine
git clone https://github.com/YOUR_USERNAME/ray-cluster.git

# Run provisioning script with your head node IP
bash ray-cluster/provision-ray-worker.sh <HEAD_NODE_IP>

# Join the cluster
~/scripts/ray-worker-start.sh

Dashboard
http://<HEAD_NODE_IP>:8265

Notes

The provisioning script is idempotent — safe to run multiple times on the
same machine. It detects what is already installed and skips those steps.
Worker nodes can join and leave the cluster at any time without affecting
the head node or other workers.
The head node IP can be overridden at runtime via environment variable:
RAY_HEAD_IP=x.x.x.x ~/scripts/ray-worker-start.sh

Stack
ComponentVersion
Ray2.55.1
Python3.12.13
PyTorch2.6.0
CUDA12.4
README
