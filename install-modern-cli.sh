#!/bin/bash
set -e

# Install a bundle of modern CLI quality-of-life tools.
#   ripgrep    — fast grep (rg)
#   fd-find    — fast find (fdfind; alias to fd in ~/.bashrc)
#   bat        — cat with syntax highlighting (batcat; alias to bat)
#   fzf        — fuzzy finder
#   zoxide     — smarter cd
#   git-delta  — better git diff viewer
#   jq, yq     — JSON / YAML query tools
#   tree, htop, ncdu — directory tree, process monitor, disk usage
#   eza        — modern ls (separate apt repo)
sudo apt-get update
sudo apt-get install -y \
    ripgrep fd-find bat fzf zoxide git-delta jq tree htop ncdu \
    gpg ca-certificates

# eza: not in default apt repos — use the maintainer's repo.
if ! command -v eza >/dev/null 2>&1; then
    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
        | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
        | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    sudo apt-get update
    sudo apt-get install -y eza
fi

# yq: not packaged on Ubuntu — grab the latest static binary from GitHub.
if ! command -v yq >/dev/null 2>&1; then
    YQ_URL="$(curl -fsSL https://api.github.com/repos/mikefarah/yq/releases/latest \
        | grep -oP 'https://[^"]*yq_linux_amd64(?!\.tar\.gz)' | head -1)"
    sudo wget -qO /usr/local/bin/yq "$YQ_URL"
    sudo chmod +x /usr/local/bin/yq
fi

# Convenience aliases for the Ubuntu-renamed binaries.
if ! grep -q '# modern-cli aliases' "$HOME/.bashrc"; then
    cat >> "$HOME/.bashrc" <<'EOF'

# modern-cli aliases
alias fd='fdfind'
alias bat='batcat'
eval "$(zoxide init bash)"
EOF
fi

# eza as the default ls (same aliases as the mac install). Separate guard so
# machines that already have the block above still pick these up.
if ! grep -q '# eza aliases' "$HOME/.bashrc"; then
    cat >> "$HOME/.bashrc" <<'EOF'

# eza aliases
alias ls='eza --group-directories-first --icons=auto'
alias ll='eza -l --group-directories-first --icons=auto --git'
alias la='eza -la --group-directories-first --icons=auto --git'
alias lt='eza --tree --level=2 --icons=auto'
EOF
fi

echo "Modern CLI tools installed. Restart your shell or run: source ~/.bashrc"
