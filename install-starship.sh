#!/bin/bash
set -e

# Install Starship prompt. See https://starship.rs/
curl -sS https://starship.rs/install.sh | sh -s -- -y

# Ensure starship init is in ~/.bashrc
if ! grep -q 'starship init bash' "$HOME/.bashrc"; then
    echo 'eval "$(starship init bash)"' >> "$HOME/.bashrc"
fi

# Apply the Gruvbox Rainbow preset, changed to show user@hostname (the preset
# shows only the username). The hostname shows on every machine, not only
# over SSH.
mkdir -p "$HOME/.config"
{
    starship preset gruvbox-rainbow \
        | awk '{ print } $0 == "$username\\" { print "$hostname\\" }' \
        | sed "s/^format = '\[\$user \](\$style)'\$/format = '[\$user](\$style)'/"
    cat <<'EOF'

[hostname]
ssh_only = false
style = "bg:color_orange fg:color_fg0"
format = '[@$hostname ]($style)'
EOF
} > "$HOME/.config/starship.toml"

echo "Starship installed with Gruvbox Rainbow preset (with user@hostname). Restart your shell or run: source ~/.bashrc"

# Set the Cascadia Code Nerd Font as the default in GNOME Terminal so the
# Starship prompt's powerline glyphs render correctly. Note: the Nerd Fonts
# patched Cascadia is registered under the family name "CaskaydiaCove Nerd Font".
TERMINAL_FONT="${TERMINAL_FONT:-CaskaydiaCove Nerd Font Mono 12}"
if command -v gsettings >/dev/null 2>&1 && [ -n "$DBUS_SESSION_BUS_ADDRESS" ]; then
    PROFILE_RAW="$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null || true)"
    PROFILE="${PROFILE_RAW//\'/}"
    if [ -n "$PROFILE" ]; then
        SCHEMA_PATH="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${PROFILE}/"
        gsettings set "$SCHEMA_PATH" use-system-font false
        gsettings set "$SCHEMA_PATH" font "$TERMINAL_FONT"
        echo "GNOME Terminal default profile font set to: $TERMINAL_FONT"
    fi
else
    echo "Skipped GNOME Terminal font setup (no graphical session detected)."
    echo "  Set your terminal's font to '$TERMINAL_FONT' manually."
fi
