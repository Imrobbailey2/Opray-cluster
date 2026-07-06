#!/bin/bash
# ============================================================
# Ray Worker Node Provisioning Script
# Provisions any Ubuntu/Debian WSL2 machine as a Ray worker
# Usage: bash provision-ray-worker.sh
# ============================================================

set -e

# ── Configuration ────────────────────────────────────────────
HEAD_TAILSCALE_IP="100.117.146.7"   # firstfolk-v2 Tailscale IP (permanent)
HEAD_PORT="6379"
PYTHON_VERSION="3.12.13"
RAY_VERSION="2.55.1"
VENV_PATH="$HOME/venvs/ray"
SCRIPTS_PATH="$HOME/scripts"
CUDA_VERSION="cu124"

# ── Colors ───────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
step() { echo -e "\n${YELLOW}--- $1 ---${NC}"; }

# ── Step 1: System check ─────────────────────────────────────
step "1/9 System Check"

log "Head node target: $HEAD_TAILSCALE_IP:$HEAD_PORT (Tailscale)"

if ! nvidia-smi &>/dev/null; then
    fail "nvidia-smi failed. Update your Windows NVIDIA driver before provisioning."
fi
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
GPU_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)
log "GPU detected: $GPU_NAME ($GPU_VRAM)"

# ── Step 2: System dependencies ──────────────────────────────
step "2/9 System Dependencies"

sudo apt-get update -qq
sudo apt-get install -y -qq \
    make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev \
    wget curl llvm libncursesw5-dev xz-utils \
    tk-dev libxml2-dev libxmlsec1-dev libffi-dev \
    liblzma-dev git netcat-openbsd 2>/dev/null
log "System dependencies installed"

# ── Step 3: Tailscale ─────────────────────────────────────────
step "3/9 Tailscale"

if command -v tailscale &>/dev/null; then
    log "Tailscale already installed -- skipping install"
else
    log "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    log "Tailscale installed"
fi

# Bring up Tailscale with WSL2-safe flags
TAILSCALE_STATUS=$(tailscale status 2>/dev/null | head -1 || echo "")
if echo "$TAILSCALE_STATUS" | grep -q "Logged out\|not logged in\|NeedsLogin\|^$"; then
    log "Authenticating Tailscale -- follow the URL below:"
    sudo tailscale up --accept-routes --netfilter-mode=off
else
    # Ensure netfilter-mode=off is set even if already authenticated
    sudo tailscale up --accept-routes --netfilter-mode=off --reset 2>/dev/null || true
    log "Tailscale already authenticated"
fi

# Detect Tailscale IP
WORKER_TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | head -1)
if [[ -z "$WORKER_TAILSCALE_IP" ]]; then
    fail "Could not detect Tailscale IP. Ensure this device is authenticated to the Imrobbailey2 tailnet."
fi
log "Worker Tailscale IP: $WORKER_TAILSCALE_IP"

# Verify connectivity to head node via Tailscale
if nc -z -w5 "$HEAD_TAILSCALE_IP" "$HEAD_PORT" 2>/dev/null; then
    log "Head node reachable at $HEAD_TAILSCALE_IP:$HEAD_PORT"
else
    warn "Cannot reach head node at $HEAD_TAILSCALE_IP:$HEAD_PORT -- ensure Ray is running on firstfolk-v2 before starting worker"
fi

# ── Step 4: pyenv ─────────────────────────────────────────────
step "4/9 pyenv"

if [[ -d "$HOME/.pyenv" ]]; then
    log "pyenv already installed -- skipping"
else
    curl -fsSL https://pyenv.run | bash
    log "pyenv installed"
fi

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)" 2>/dev/null

if ! grep -q 'PYENV_ROOT' ~/.bashrc; then
    cat >> ~/.bashrc << 'PYENVEOF'

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
PYENVEOF
    log "pyenv added to .bashrc"
else
    log "pyenv already in .bashrc -- skipping"
fi

# ── Step 5: Python 3.12.13 ───────────────────────────────────
step "5/9 Python $PYTHON_VERSION"

if pyenv versions | grep -q "$PYTHON_VERSION"; then
    log "Python $PYTHON_VERSION already installed via pyenv -- skipping"
else
    log "Compiling Python $PYTHON_VERSION (this takes 3-5 minutes)..."
    pyenv install "$PYTHON_VERSION"
    log "Python $PYTHON_VERSION installed"
fi

PYTHON_BIN="$HOME/.pyenv/versions/$PYTHON_VERSION/bin/python3"

# ── Step 6: Ray venv ─────────────────────────────────────────
step "6/9 Ray Virtual Environment"

if [[ -d "$VENV_PATH" ]]; then
    EXISTING_PYTHON=$("$VENV_PATH/bin/python" --version 2>&1)
    if echo "$EXISTING_PYTHON" | grep -q "$PYTHON_VERSION"; then
        log "Ray venv exists with correct Python -- skipping"
    else
        warn "Ray venv uses wrong Python ($EXISTING_PYTHON) -- rebuilding"
        rm -rf "$VENV_PATH"
        "$PYTHON_BIN" -m venv "$VENV_PATH"
        log "Ray venv rebuilt with Python $PYTHON_VERSION"
    fi
else
    mkdir -p ~/venvs
    "$PYTHON_BIN" -m venv "$VENV_PATH"
    log "Ray venv created at $VENV_PATH"
fi

source "$VENV_PATH/bin/activate"

# ── Step 7: Ray & PyTorch ────────────────────────────────────
step "7/9 Ray $RAY_VERSION + PyTorch"

pip install --upgrade pip -q

INSTALLED_RAY=$(python -c "import ray; print(ray.__version__)" 2>/dev/null || echo "none")
if [[ "$INSTALLED_RAY" == "$RAY_VERSION" ]]; then
    log "Ray $RAY_VERSION already installed -- skipping"
else
    log "Installing Ray $RAY_VERSION..."
    pip install -q "ray[default,air,serve,train,tune,data]==$RAY_VERSION"
    log "Ray $RAY_VERSION installed"
fi

INSTALLED_TORCH=$(python -c "import torch; print(torch.__version__)" 2>/dev/null || echo "none")
if [[ "$INSTALLED_TORCH" != "none" ]]; then
    log "PyTorch already installed ($INSTALLED_TORCH) -- skipping"
else
    log "Installing PyTorch (CUDA $CUDA_VERSION)..."
    pip install -q torch --index-url "https://download.pytorch.org/whl/$CUDA_VERSION"
    log "PyTorch installed"
fi

# ── Step 8: Systemd Worker Service ───────────────────────────
step "8/9 Systemd Worker Service"

SERVICE_FILE="/etc/systemd/system/ray-worker.service"

sudo tee "$SERVICE_FILE" > /dev/null << SERVICEEOF
[Unit]
Description=Ray Worker Node for Opray-Cluster
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME
ExecStart=/bin/bash -c 'source $VENV_PATH/bin/activate && \\
  ray start \\
    --address=$HEAD_TAILSCALE_IP:$HEAD_PORT \\
    --node-ip-address=$WORKER_TAILSCALE_IP \\
    --node-manager-port=20001 \\
    --object-manager-port=10002 \\
    --min-worker-port=20002 \\
    --max-worker-port=20100 \\
    --num-gpus=1 \\
    --disable-usage-stats \\
    --block'
Restart=always
RestartSec=30
Environment=RAY_DISABLE_MEMORY_MONITOR=1
Environment=RAY_USAGE_STATS_ENABLED=0
Environment=RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO=0
Environment=RAY_health_check_timeout_ms=15000
Environment=RAY_worker_proc_graceful_shutdown_timeout_s=60

[Install]
WantedBy=multi-user.target
SERVICEEOF

sudo systemctl daemon-reload
sudo systemctl enable ray-worker.service
log "ray-worker.service installed and enabled"
log "  Head:   $HEAD_TAILSCALE_IP:$HEAD_PORT"
log "  Worker: $WORKER_TAILSCALE_IP"

# ── Step 9: Shell Environment ─────────────────────────────────
step "9/9 Shell Environment"

declare -A ENV_VARS=(
    ["RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO"]="0"
    ["RAY_DISABLE_MEMORY_MONITOR"]="1"
    ["RAY_USAGE_STATS_ENABLED"]="0"
)

for VAR in "${!ENV_VARS[@]}"; do
    if ! grep -q "$VAR" ~/.bashrc; then
        echo "export $VAR=${ENV_VARS[$VAR]}" >> ~/.bashrc
        log "$VAR added to .bashrc"
    else
        log "$VAR already in .bashrc -- skipping"
    fi
done

if ! grep -q 'alias rayenv' ~/.bashrc; then
    echo "alias rayenv='source $VENV_PATH/bin/activate'" >> ~/.bashrc
    log "rayenv alias added to .bashrc"
else
    log "rayenv alias already in .bashrc -- skipping"
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}   Provisioning Complete                        ${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "  GPU:            $GPU_NAME ($GPU_VRAM)"
echo "  Tailscale IP:   $WORKER_TAILSCALE_IP"
echo "  Head Node:      $HEAD_TAILSCALE_IP:$HEAD_PORT"
echo "  Python:         $PYTHON_VERSION"
echo "  Ray:            $RAY_VERSION"
echo ""
echo "  To start the worker now:"
echo "    sudo systemctl start ray-worker.service"
echo ""
echo "  To check worker status:"
echo "    sudo systemctl status ray-worker.service"
echo ""
echo "  Worker will auto-start on next boot via systemd."
echo ""
