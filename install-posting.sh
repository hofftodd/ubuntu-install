#!/bin/bash
set -e

# Install Posting, API client (HTTP requests, collections, environments) for
# the terminal. See https://posting.sh and https://github.com/darrenburns/posting
# It's a Python app; upstream recommends installing it with `uv tool`, which
# puts it in ~/.local/bin.
if ! command -v uv >/dev/null 2>&1; then
    echo "uv not found — run install-uv.sh, then re-run this script." >&2
    exit 1
fi

# Re-running is a no-op if it's already installed. Upgrade with: uv tool upgrade posting
uv tool install posting

# Make sure ~/.local/bin is on PATH.
if ! grep -q '\.local/bin' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

echo "posting installed in $HOME/.local/bin. Run: posting"
