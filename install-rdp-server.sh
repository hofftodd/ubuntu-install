#!/bin/bash
set -euo pipefail

# Set up an RDP server using GNOME Remote Desktop's *system* daemon ("Remote
# Login"), which is the native remote-desktop stack on Ubuntu 26.04/GNOME and
# the only one that works properly under Wayland.
#
# System mode is headless: connecting starts a brand-new GNOME session for you,
# so nobody has to be sitting at the machine. That's different from GNOME's
# "Desktop Sharing" (user mode), which mirrors an already-running session.
#
# Authentication is PAM-based — you log in with your normal Linux username and
# password. There is no separate RDP password to set.
#
# Overrides:
#   RDP_PORT=3389        port the server binds to
#   RDP_CERT_DAYS=3650   lifetime of the generated self-signed TLS cert
RDP_PORT="${RDP_PORT:-3389}"
RDP_CERT_DAYS="${RDP_CERT_DAYS:-3650}"

CERT_DIR=/etc/gnome-remote-desktop
CERT="$CERT_DIR/rdp-tls.crt"
KEY="$CERT_DIR/rdp-tls.key"

sudo apt-get update
sudo apt-get install -y gnome-remote-desktop openssl

# The system daemon runs as the unprivileged `gnome-remote-desktop` user and
# must be able to read the key, so generate the pair as that user.
sudo install -d -o gnome-remote-desktop -g gnome-remote-desktop -m 755 "$CERT_DIR"
if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
    sudo -u gnome-remote-desktop openssl req -new -newkey rsa:4096 \
        -days "$RDP_CERT_DAYS" -nodes -x509 \
        -subj "/CN=$(hostname)" \
        -out "$CERT" -keyout "$KEY"
    sudo chmod 600 "$KEY"
    echo "Generated a self-signed TLS certificate valid for $RDP_CERT_DAYS days."
else
    echo "Reusing existing TLS certificate at $CERT."
fi

sudo grdctl --system rdp set-tls-cert "$CERT"
sudo grdctl --system rdp set-tls-key "$KEY"
sudo grdctl --system rdp set-port "$RDP_PORT"
sudo grdctl --system rdp set-auth-methods credentials
sudo grdctl --system rdp enable

sudo systemctl enable --now gnome-remote-desktop.service

# Open the port if ufw is installed and actually on — leave it alone otherwise.
if command -v ufw > /dev/null && sudo ufw status | grep -q "^Status: active"; then
    sudo ufw allow "$RDP_PORT"/tcp
    echo "Opened port $RDP_PORT/tcp in ufw."
fi

sudo grdctl --system status

IP=$(hostname -I | awk '{print $1}')
echo
echo "RDP server running on port $RDP_PORT."
echo "  Connect to:  ${IP:-<this-host>}:$RDP_PORT   (or $(hostname):$RDP_PORT)"
echo "  Log in as:   $USER, with your normal Linux password"
echo
echo "The certificate is self-signed, so clients will warn on first connect."
echo "Remote Login opens a *new* session — log out of the physical console first,"
echo "or GNOME will refuse the second session for the same user."
