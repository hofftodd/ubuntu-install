#!/bin/bash
set -e

# Install Frogmouth, Markdown browser for the terminal (local files, URLs and
# GitHub READMEs). See https://github.com/Textualize/frogmouth
# It's a Python app, installed with `uv tool` into ~/.local/bin.
if ! command -v uv >/dev/null 2>&1; then
    echo "uv not found — run install-uv.sh, then re-run this script." >&2
    exit 1
fi

# Frogmouth 0.9.x pins an old httpx/httpcore that crashes on start under
# Python 3.14+ ('typing.Union' object has no attribute '__module__'), so it
# gets its own Python (uv downloads it if needed). Override with
# FROGMOUTH_PYTHON=3.x once a newer frogmouth release fixes that.
FROGMOUTH_PYTHON="${FROGMOUTH_PYTHON:-3.13}"

# Re-running is a no-op if it's already installed on that Python (uv
# reinstalls it if it's on a different one). Upgrade with: uv tool upgrade frogmouth
uv tool install --python "$FROGMOUTH_PYTHON" frogmouth

# Make sure ~/.local/bin is on PATH.
if ! grep -q '\.local/bin' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

echo "frogmouth installed in $HOME/.local/bin. Try: frogmouth README.md"
