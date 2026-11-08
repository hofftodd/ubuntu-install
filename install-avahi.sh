#!/bin/bash
set -euo pipefail

# Avahi mDNS/DNS-SD: advertise this machine as <hostname>.local and resolve
# other .local hosts and services on the LAN.
#   avahi-daemon — the mDNS/DNS-SD responder (systemd service)
#   avahi-utils  — avahi-browse / avahi-resolve / avahi-publish CLI tools
#   libnss-mdns  — lets ping/ssh/etc. resolve *.local names via nsswitch
sudo apt-get update
sudo apt-get install -y avahi-daemon avahi-utils libnss-mdns

sudo systemctl enable --now avahi-daemon.service

# Allow mDNS if ufw is installed and actually on — leave it alone otherwise.
if command -v ufw > /dev/null && sudo ufw status | grep -q "^Status: active"; then
    sudo ufw allow 5353/udp
    echo "Opened port 5353/udp (mDNS) in ufw."
fi

echo "Avahi installed and running. This machine is reachable as $(hostname).local"
echo "  Browse services:   avahi-browse -art"
echo "  Resolve a host:    avahi-resolve -n <host>.local"
