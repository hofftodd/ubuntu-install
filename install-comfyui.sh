#!/bin/bash
set -e

# Install ComfyUI, the node-graph UI for Stable Diffusion / video models.
# See https://github.com/comfyanonymous/ComfyUI
#
# ComfyUI is a Python app, not a package — it runs from a git checkout with its
# own venv. This script clones it, builds the venv, installs the right PyTorch
# for your GPU, and drops a `comfyui` launcher into ~/.local/bin.
#
# Overrides:
#   COMFY_DIR=~/src/ComfyUI      where to clone
#   COMFY_BACKEND=auto           auto | rocm | cuda | cpu
#   COMFY_TORCH_INDEX=<url>      PyTorch wheel index (overrides the backend default)
#   COMFY_MANAGER=1              also install ComfyUI-Manager (set 0 to skip)
#   COMFY_MODELS=0               set 1 to download a ~23GB starter model set
#   COMFY_SERVICE=0              set 1 to enable a per-user systemd service
#   COMFY_PORT=8188              port the server (and service) listens on
COMFY_DIR="${COMFY_DIR:-$HOME/src/ComfyUI}"
COMFY_BACKEND="${COMFY_BACKEND:-auto}"
COMFY_MANAGER="${COMFY_MANAGER:-1}"
COMFY_MODELS="${COMFY_MODELS:-0}"
COMFY_SERVICE="${COMFY_SERVICE:-0}"
COMFY_PORT="${COMFY_PORT:-8188}"

VENV="$COMFY_DIR/.venv"

# --- Pick a backend -------------------------------------------------------
# nvidia-smi is the reliable NVIDIA tell; /dev/kfd is the AMD compute device,
# present once the amdgpu kernel driver is loaded. Neither means CPU-only.
if [ "$COMFY_BACKEND" = "auto" ]; then
    if command -v nvidia-smi > /dev/null; then
        COMFY_BACKEND=cuda
    elif [ -e /dev/kfd ]; then
        COMFY_BACKEND=rocm
    else
        COMFY_BACKEND=cpu
    fi
    echo "Detected backend: $COMFY_BACKEND"
fi

# Wheel channels go stale as PyTorch ships new ROCm/CUDA builds. Browse
# https://download.pytorch.org/whl/ and override COMFY_TORCH_INDEX if needed.
case "$COMFY_BACKEND" in
    rocm) TORCH_INDEX="${COMFY_TORCH_INDEX:-https://download.pytorch.org/whl/rocm7.2}" ;;
    cuda) TORCH_INDEX="${COMFY_TORCH_INDEX:-https://download.pytorch.org/whl/cu130}" ;;
    cpu)  TORCH_INDEX="${COMFY_TORCH_INDEX:-https://download.pytorch.org/whl/cpu}" ;;
    *)
        echo "Unknown COMFY_BACKEND: $COMFY_BACKEND (want auto, rocm, cuda or cpu)" >&2
        exit 1
        ;;
esac

sudo apt-get update
sudo apt-get install -y git python3 python3-venv python3-pip

# --- Clone or update ------------------------------------------------------
mkdir -p "$(dirname "$COMFY_DIR")"
if [ -d "$COMFY_DIR/.git" ]; then
    echo "Updating existing checkout at $COMFY_DIR..."
    git -C "$COMFY_DIR" pull --ff-only
else
    git clone https://github.com/comfyanonymous/ComfyUI "$COMFY_DIR"
fi

# --- Virtualenv -----------------------------------------------------------
# uv is dramatically faster at this — the torch wheels run to several GB — so
# use it when install-uv.sh has been run, and fall back to stdlib venv+pip.
if command -v uv > /dev/null; then
    [ -x "$VENV/bin/python" ] || uv venv "$VENV"
    pip_install() { uv pip install --python "$VENV/bin/python" "$@"; }
else
    [ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
    "$VENV/bin/pip" install --upgrade pip
    pip_install() { "$VENV/bin/pip" install "$@"; }
fi

# Torch first, from the backend-specific index. ComfyUI's requirements.txt
# lists torch unpinned, so installing it here means the generic PyPI build
# (which is CUDA-only) never gets pulled in behind our backs.
echo "Installing PyTorch for $COMFY_BACKEND from $TORCH_INDEX ..."
pip_install --index-url "$TORCH_INDEX" torch torchvision torchaudio

pip_install -r "$COMFY_DIR/requirements.txt"

# --- ComfyUI-Manager ------------------------------------------------------
# The de-facto standard custom node: installs/updates other custom nodes and
# models from inside the web UI.
if [ "$COMFY_MANAGER" = "1" ]; then
    MANAGER_DIR="$COMFY_DIR/custom_nodes/ComfyUI-Manager"
    if [ -d "$MANAGER_DIR/.git" ]; then
        git -C "$MANAGER_DIR" pull --ff-only
    else
        git clone https://github.com/Comfy-Org/ComfyUI-Manager "$MANAGER_DIR"
    fi
    if [ -f "$MANAGER_DIR/requirements.txt" ]; then
        pip_install -r "$MANAGER_DIR/requirements.txt"
    fi
fi

# --- Starter models -------------------------------------------------------
# ComfyUI ships no weights at all — a fresh checkout gives you a UI where every
# loader node has an empty dropdown. This pulls a usable starter set so the
# install boots to something you can actually render with.
#
# Off by default: it's ~23GB, and re-running this script to update the checkout
# shouldn't re-litigate that. Set COMFY_MODELS=1 the first time.
#
# Everything here is ungated so no credentials are needed. black-forest-labs'
# own FLUX repos now 401 without an accepted license, so Flux comes from
# Comfy-Org's mirror as the all-in-one fp8 checkpoint (UNet + CLIP-L + T5 + VAE
# in one file, loads with a plain Load Checkpoint node). Set HF_TOKEN to reach
# gated repos if you swap in flux1-dev.
if [ "$COMFY_MODELS" = "1" ]; then
    # subdir|filename|url
    MODELS=(
        "checkpoints|flux1-schnell-fp8.safetensors|https://huggingface.co/Comfy-Org/flux1-schnell/resolve/main/flux1-schnell-fp8.safetensors"
        "checkpoints|sd_xl_base_1.0.safetensors|https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors"
        "vae|sdxl_vae.safetensors|https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors"
    )

    # Only needed for gated repos; the set above doesn't use it.
    AUTH=()
    [ -n "${HF_TOKEN:-}" ] && AUTH=(-H "Authorization: Bearer $HF_TOKEN")

    echo
    echo "Downloading starter models (~23GB) into $COMFY_DIR/models ..."
    for entry in "${MODELS[@]}"; do
        IFS='|' read -r subdir filename url <<< "$entry"
        dest="$COMFY_DIR/models/$subdir/$filename"
        if [ -s "$dest" ]; then
            echo "  have    $subdir/$filename"
            continue
        fi
        echo "  fetch   $subdir/$filename"
        mkdir -p "$(dirname "$dest")"

        # HuggingFace exposes the LFS object's sha256 as x-linked-etag, so we
        # get a real integrity check without hardcoding hashes that would go
        # stale whenever a repo updates.
        expect_sha=$(curl -sIL ${AUTH[@]+"${AUTH[@]}"} "$url" \
            | grep -i '^x-linked-etag:' | tail -1 | tr -d '\r"' | awk '{print $2}')

        # Download to .part and rename only on success, so an interrupted pull
        # never leaves a truncated file that looks complete on the next run.
        # Resume that .part only when one is actually there — curl errors out
        # on -C - with no existing output file.
        RESUME=()
        [ -f "$dest.part" ] && RESUME=(-C -)
        curl -fL --retry 3 --retry-delay 5 \
            ${RESUME[@]+"${RESUME[@]}"} ${AUTH[@]+"${AUTH[@]}"} \
            -o "$dest.part" "$url"

        # A .part left over from a different URL resumes into a file of exactly
        # the right length but the wrong bytes, so size proves nothing here —
        # only the hash does. A 16GB checkpoint that is quietly corrupt is
        # miserable to debug, so pay the ~1min of hashing and be certain.
        if [ -n "$expect_sha" ]; then
            echo "  verify  $subdir/$filename"
            got_sha=$(sha256sum "$dest.part" | awk '{print $1}')
            if [ "$got_sha" != "$expect_sha" ]; then
                rm -f "$dest.part"
                echo "  ERROR: $filename failed its checksum and was discarded." >&2
                echo "         expected $expect_sha" >&2
                echo "         got      $got_sha" >&2
                echo "         Re-run the script — the retry starts from scratch." >&2
                exit 1
            fi
        fi
        mv "$dest.part" "$dest"
    done
    echo "Starter models ready."
fi

# --- Launcher -------------------------------------------------------------
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/comfyui" <<EOF
#!/bin/bash
# Launch ComfyUI. Extra args are passed straight through to main.py,
# e.g. comfyui --listen 0.0.0.0 --lowvram
exec "$VENV/bin/python" "$COMFY_DIR/main.py" --port "\${COMFY_PORT:-$COMFY_PORT}" "\$@"
EOF
chmod +x "$HOME/.local/bin/comfyui"

if ! grep -q '\.local/bin' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

# --- Optional systemd user service ---------------------------------------
# Off by default: ComfyUI parks several GB of weights in VRAM once it's serving,
# which you rarely want running at every login.
UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"
cat > "$UNIT_DIR/comfyui.service" <<EOF
[Unit]
Description=ComfyUI
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$COMFY_DIR
ExecStart=$HOME/.local/bin/comfyui
Restart=on-failure

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload 2>/dev/null || true

if [ "$COMFY_SERVICE" = "1" ]; then
    systemctl --user enable --now comfyui.service
    echo "Enabled the comfyui per-user service."
fi

echo
echo "ComfyUI installed at $COMFY_DIR (backend: $COMFY_BACKEND)."
echo "  Run:      comfyui            (then open http://localhost:$COMFY_PORT)"
echo "  Update:   re-run this script — it pulls and reinstalls in place"
if [ "$COMFY_MODELS" = "1" ]; then
    echo "  Models:   starter set in $COMFY_DIR/models/checkpoints"
else
    echo "  Models:   none installed — re-run with COMFY_MODELS=1 for a ~23GB"
    echo "            starter set, add your own to $COMFY_DIR/models/checkpoints,"
    echo "            or pull them from the Manager tab in the web UI"
fi
echo "  Service:  systemctl --user start comfyui   (enable with COMFY_SERVICE=1)"

# AMD needs the amdgpu kernel driver plus render/video group membership for
# /dev/kfd. The torch ROCm wheels bundle the ROCm runtime, so a full ROCm
# install isn't required — but the groups are.
if [ "$COMFY_BACKEND" = "rocm" ] && ! id -nG | grep -qw render; then
    echo
    echo "NOTE: $USER is not in the 'render' group. A seated desktop session gets a"
    echo "      temporary ACL on /dev/kfd, but headless and RDP sessions don't — so"
    echo "      GPU compute will fail there. Run ./install-amd-drivers.sh (or"
    echo "      'sudo usermod -aG render,video $USER') and log out and back in."
fi
