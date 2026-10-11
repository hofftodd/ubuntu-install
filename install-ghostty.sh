#!/bin/bash
set -e

# Install the Ghostty terminal emulator (https://ghostty.org/).
# Ghostty doesn't ship official Linux binaries. Prefer the Ubuntu archive
# package when the release has one; otherwise fall back to the snap
# (classic confinement, auto-updates).

sudo apt-get update

if [ -n "$(apt-cache policy ghostty 2>/dev/null | awk '/Candidate:/ && $2 != "(none)" {print $2}')" ]; then
    sudo apt-get install -y ghostty
else
    if ! command -v snap >/dev/null 2>&1; then
        sudo apt-get install -y snapd
    fi
    sudo snap install ghostty --classic
fi

# Seed a minimal config matching install-starship.sh's Nerd Font, but never
# overwrite an existing one (either config filename).
CONFIG_DIR="$HOME/.config/ghostty"
if [ ! -e "$CONFIG_DIR/config" ] && [ ! -e "$CONFIG_DIR/config.ghostty" ]; then
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/config" <<'CONF'
# See `ghostty +show-config --default --docs` for all options.
font-family = CaskaydiaCove Nerd Font Mono
font-size = 12
CONF
    echo "Wrote starter config to $CONFIG_DIR/config"
fi

echo "Ghostty installed: $(ghostty --version 2>/dev/null | head -1)"
