#!/bin/bash
set -e

# Install lazydocker, terminal UI for Docker and Docker Compose.
# See https://github.com/jesseduffield/lazydocker
# Works with whichever Docker engine is running (Docker Desktop or docker-ce).
# Not in Ubuntu's apt repos, so this pulls the latest release tarball for the
# host architecture from GitHub, checks it against the release's
# checksums.txt, and puts the binary in ~/.local/bin.
REPO=jesseduffield/lazydocker
BIN=lazydocker

sudo apt-get update
sudo apt-get install -y curl jq ca-certificates

case "$(dpkg --print-architecture)" in
    amd64) ARCH=x86_64 ;;
    arm64) ARCH=arm64 ;;
    *)
        echo "No prebuilt $BIN for arch '$(dpkg --print-architecture)'." >&2
        exit 1
        ;;
esac

RELEASE="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")"
# Assets are named <tool>_<version>_Linux_<arch>.tar.gz; match "linux" in
# either case (lazydocker capitalises it, lazygit doesn't).
ASSET="$(echo "$RELEASE" | jq -r --arg arch "$ARCH" \
    '.assets[].name | select(test("_linux_" + $arch + "\\.tar\\.gz$"; "i"))' | head -1)"
if [ -z "$ASSET" ]; then
    echo "Could not find a $BIN tarball for $ARCH in the latest release." >&2
    exit 1
fi
url_of() { echo "$RELEASE" | jq -r --arg n "$1" '.assets[] | select(.name == $n) | .browser_download_url'; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$(url_of "$ASSET")" -o "$TMP/$ASSET"
curl -fsSL "$(url_of checksums.txt)" -o "$TMP/checksums.txt"
(cd "$TMP" && grep " $ASSET\$" checksums.txt | sha256sum -c -)

tar -xzf "$TMP/$ASSET" -C "$TMP" "$BIN"
mkdir -p "$HOME/.local/bin"
install -m 755 "$TMP/$BIN" "$HOME/.local/bin/$BIN"

# Make sure ~/.local/bin is on PATH.
if ! grep -q '\.local/bin' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

echo "$BIN installed: $("$HOME/.local/bin/$BIN" --version | head -1)"
echo "Restart your shell or run: source ~/.bashrc"
