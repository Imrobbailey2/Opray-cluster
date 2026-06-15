# Ray Cluster

Distributed GPU compute cluster for LLM inference, rendering, ML training, and computational imaging.

---

## Cluster Nodes

| Role | GPU | VRAM |
|---|---|---|
| Head Node + Primary Worker | NVIDIA RTX A4000 | 16GB |
| Worker 1 | NVIDIA RTX A1000 | 6GB |
| Worker 2 | NVIDIA RTX A4000 | 16GB |

---

## Requirements

- Windows 11 with WSL2 (Ubuntu 24.04 or newer)
- NVIDIA GPU with CUDA 12.4 compatible driver (610.x or newer recommended)
- Python 3.12.13 (installed automatically by provisioning script)
- Machines on the same network segment or routable between segments
- Machines must be domain-joined or on the same subnet

---

## Adding a New Worker — Complete Process

> ⚠️ Every new worker machine requires **TWO** provisioning steps: a Windows-side step and a Linux-side step. Skipping the Windows step will cause the worker to repeatedly disconnect from the cluster due to firewall-blocked health checks.

### Step 1 — Windows Provisioning (PowerShell, run as Administrator)

Run the included PowerShell script on the new worker machine **before anything else**:

```powershell
provision-ray-worker-windows.ps1
```

This script:
- Configures WSL2 mirrored networking
- Opens the required Ray ports in Windows Defender Firewall (Domain profile)

Without this step, the GCS health check from the head node will be blocked on port 20001 and the worker raylet will self-terminate after approximately 30–45 seconds.

After the script completes, restart WSL2:

```powershell
wsl --shutdown
```

Then relaunch your Ubuntu terminal and verify networking:

```bash
# Must return a 10.x.x.x LAN address — not 172.x.x.x or 169.254.x.x
hostname -I
ip route get 8.8.8.8 | awk '{print $7; exit}'
```

Also verify your GPU is accessible:

```bash
nvidia-smi
# If this segfaults, update your Windows NVIDIA driver to 610.x or newer before proceeding
```

---

### Step 2 — Linux Provisioning (WSL2 Ubuntu terminal)

Clone this repo and run the provisioning script:

```bash
git clone https://github.com/Imrobbailey2/Opray-cluster.git
bash Opray-cluster/provision-ray-worker.sh <HEAD_NODE_IP>
```

The provisioning script is **idempotent** — safe to run multiple times on the same machine. It detects what is already installed and skips those steps. On a fresh machine expect 5–10 minutes for Python compilation.

---

### Step 3 — Join the Cluster

```bash
RAY_HEAD_IP=<HEAD_NODE_IP> ~/scripts/ray-worker-start.sh
```

The worker should appear in the dashboard within 30 seconds and remain connected. If it disconnects, verify the Windows firewall rules were applied in Step 1.

---

## Head Node

### Starting the Head Node (run once per WSL2 session)

```bash
source ~/venvs/ray/bin/activate
~/scripts/ray-head-start.sh
```

---

## Dashboard

```
http://<HEAD_NODE_IP>:8265
```

The dashboard shows all connected nodes, GPU availability, VRAM usage, and job queue status.

---

## Known Issues and Fixes

### WSL2 cgroup memory monitor
WSL2 does not expose cgroup memory information correctly. Ray's memory monitor will log warnings about negative memory values. This is resolved by setting `memory_monitor_refresh_ms` to `0` in the head node `--system-config`, which is already included in `ray-head-start.sh`. The setting propagates automatically to all workers.

### Windows Firewall blocking health checks
Ray's GCS server performs periodic health checks from the head node to each worker on port `20001`. If Windows Defender Firewall blocks this port on the worker, the worker raylet self-terminates after missing the configured number of health checks. This is resolved by `provision-ray-worker-windows.ps1`.

### WSL2 NAT vs mirrored networking
If `hostname -I` returns a `172.x.x.x` address, WSL2 is in NAT mode. Workers in NAT mode register with an unreachable IP and immediately fail to receive health checks. Enable mirrored networking via the Windows provisioning script.

### Python version mismatch
All nodes must run the **exact same Python patch version**. This cluster uses Python 3.12.13. The provisioning script installs this version via pyenv regardless of the system Python version.

### Worker nodes joining and leaving
Workers can join and leave the cluster at any time without affecting the head node or other workers. Simply run `ray-worker-start.sh` to rejoin after a restart.

---

## Stack

| Component | Version |
|---|---|
| Ray | 2.55.1 |
| Python | 3.12.13 |
| PyTorch | 2.6.0 |
| CUDA | 12.4 |
