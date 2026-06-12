#!/bin/bash
# ============================================================
# Ray Worker Node Provisioning Script
# Provisions any Ubuntu/Debian WSL2 machine as a Ray worker
# Usage: bash provision-ray-worker.sh [HEAD_NODE_IP]
# ============================================================

set -e

# ── Configuration ────────────────────────────────────────────
HEAD_IP="${1:-10.242.22.65}"
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
step "1/8 System Check"

WORKER_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')
if [[ -z "$WORKER_IP" ]]; then
    WORKER_IP=$(hostname -I | awk '{print $1}')
fi
log "Worker IP detected: $WORKER_IP"
log "Head node target:   $HEAD_IP:$HEAD_PORT"

if ! nvidia-smi &>/dev/null; then
    fail "nvidia-smi failed. Update your Windows NVIDIA driver before provisioning."
fi
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
GPU_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)
log "GPU detected: $GPU_NAME ($GPU_VRAM)"

if ! nc -z -w5 "$HEAD_IP" "$HEAD_PORT" 2>/dev/null; then
    warn "Cannot reach head node at $HEAD_IP:$HEAD_PORT -- check network before running ray-worker-start.sh"
else
    log "Head node reachable at $HEAD_IP:$HEAD_PORT"
fi

# ── Step 2: System dependencies ──────────────────────────────
step "2/8 System Dependencies"

sudo apt-get update -qq
sudo apt-get install -y -qq \
    make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev \
    wget curl llvm libncursesw5-dev xz-utils \
    tk-dev libxml2-dev libxmlsec1-dev libffi-dev \
    liblzma-dev git netcat-openbsd 2>/dev/null
log "System dependencies installed"

# ── Step 3: pyenv ─────────────────────────────────────────────
step "3/8 pyenv"

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

# ── Step 4: Python 3.12.13 ───────────────────────────────────
step "4/8 Python $PYTHON_VERSION"

if pyenv versions | grep -q "$PYTHON_VERSION"; then
    log "Python $PYTHON_VERSION already installed via pyenv -- skipping"
else
    log "Compiling Python $PYTHON_VERSION (this takes 3-5 minutes)..."
    pyenv install "$PYTHON_VERSION"
    log "Python $PYTHON_VERSION installed"
fi

PYTHON_BIN="$HOME/.pyenv/versions/$PYTHON_VERSION/bin/python3"

# ── Step 5: Ray venv ─────────────────────────────────────────
step "5/8 Ray Virtual Environment"

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

# ── Step 6: Ray & PyTorch ────────────────────────────────────
step "6/8 Ray $RAY_VERSION + PyTorch"

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

# ── Step 7: Worker start script ──────────────────────────────
step "7/8 Worker Start Script"

mkdir -p "$SCRIPTS_PATH"

cat > "$SCRIPTS_PATH/ray-worker-start.sh" << WORKEREOF
#!/bin/bash
export RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO=0
# Ray Worker Node Startup Script
# Auto-provisioned $(date)
# GPU: $GPU_NAME

source $VENV_PATH/bin/activate

HEAD_IP="$HEAD_IP"
WORKER_IP="$WORKER_IP"

echo "Joining Ray cluster at: \$HEAD_IP:$HEAD_PORT"
echo "Worker IP: \$WORKER_IP"

ray start \\
  --address=\$HEAD_IP:$HEAD_PORT \\
  --node-ip-address=\$WORKER_IP \\
  --node-manager-port=20001 \\
  --object-manager-port=10002 \\
  --min-worker-port=20002 \\
  --max-worker-port=20100 \\
  --num-gpus=1 \\
  --disable-usage-stats \\
  --verbose
WORKEREOF

chmod +x "$SCRIPTS_PATH/ray-worker-start.sh"
log "Worker start script written to $SCRIPTS_PATH/ray-worker-start.sh"

# ── Step 8: Shell environment ─────────────────────────────────
step "8/8 Shell Environment"

if ! grep -q 'RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO' ~/.bashrc; then
    echo 'export RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO=0' >> ~/.bashrc
    log "RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO added to .bashrc"
else
    log "RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO already in .bashrc"
fi

if ! grep -q 'alias rayenv' ~/.bashrc; then
    echo "alias rayenv='source $VENV_PATH/bin/activate'" >> ~/.bashrc
    log "rayenv alias added to .bashrc"
else
    log "rayenv alias already in .bashrc"
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}   Provisioning Complete                        ${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "  GPU:        $GPU_NAME ($GPU_VRAM)"
echo "  Worker IP:  $WORKER_IP"
echo "  Head Node:  $HEAD_IP:$HEAD_PORT"
echo "  Python:     $PYTHON_VERSION"
echo "  Ray:        $RAY_VERSION"
echo ""
echo "  To join the cluster run:"
echo "    ~/scripts/ray-worker-start.sh"
echo ""
