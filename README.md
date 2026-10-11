# ubuntu-install

A collection of small, idempotent install scripts for setting up a fresh Ubuntu workstation. Each script handles one tool; `install-master.sh` runs them via an interactive category menu.

## Background

This project was vibe coded with [Claude Code](https://claude.com/claude-code) — two birds, one stone: I wanted a reproducible way to spin my development environment back up on a new machine, and I wanted to learn how to vibe code with Claude in the process.

## Usage

### Bootstrap (fresh machine)

On a brand-new Ubuntu install, you don't have this repo yet. Run the bootstrap one-liner — it installs git+ssh, prompts for your git name and email, generates an SSH key, prints it for you to paste into GitHub, then clones this repo.

```bash
curl -fsSL https://raw.githubusercontent.com/hofftodd/ubuntu-install/main/bootstrap.sh | bash
```

To run non-interactively (e.g. in a script):

```bash
curl -fsSL https://raw.githubusercontent.com/hofftodd/ubuntu-install/main/bootstrap.sh \
  | GIT_USER_NAME="Jane Doe" GIT_USER_EMAIL="jane@example.com" bash
```

Then:

```bash
cd ~/ubuntu-install
./install-master.sh
```

`bootstrap.sh` is **not** part of `install-master.sh` — it's the chicken-and-egg step.

### After bootstrap

Run a single script:

```bash
./install-vscode.sh
```

Or run the menu:

```bash
./install-master.sh
```

`install-master.sh` is a pure-bash TUI with a collapsible category tree, arrow-key navigation, and checkboxes. It runs the selected scripts and **continues past failures**, capturing per-script logs in a temp directory and printing a punch list at the end. Press `r` inside the menu to view this README without leaving it.

Refresh the pinned version defaults (Go, nvm, Python, Nerd Fonts) from upstream before installing:

```bash
./update-versions.sh
```

`install-master.sh` runs this automatically as its first step.

Most scripts that download a pinned version also expose an env var override, e.g.:

```bash
PYTHON_VERSION=3.13.0       ./install-pyenv.sh
GO_VERSION=1.24.0           ./install-go.sh
NODE_VERSION=22             ./install-nodejs.sh
JAVA_VERSION=21.0.5-tem     ./install-sdkman.sh
BACKEND=cpu                 ./install-llamacpp.sh   # default is vulkan
USECASE=graphics            ./install-amd-drivers.sh
```

## What's included

These categories match the menu layout in `install-master.sh`.

### Setup
- `update-versions.sh` — refresh pinned tool versions (Go, nvm, Python, Nerd Fonts) from upstream APIs and rewrite the defaults in the relevant install scripts.

### Drivers / base
- `install-flatpak.sh` — Flatpak runtime + Flathub remote.
- `install-amd-drivers.sh` — AMD GPU drivers + ROCm via the official `amdgpu-install` package. Adds you to the `render` and `video` groups (logout required). Default-deselected in the menu — Ubuntu 26 ships modern amdgpu in-kernel.

### Git / GitHub
- `install-git-config.sh` — global git config: `user.name`/`user.email` (prompts if not set; or pass `GIT_USER_NAME`/`GIT_USER_EMAIL`), modern defaults (rebase pulls, autoSetupRemote, zdiff3, rerere), aliases. Auto-wires `git-delta` as the pager if installed.
- `install-gh.sh` — GitHub CLI (`gh`).

### Languages
- `install-sdkman.sh` — SDKMAN! plus Java (latest Eclipse Temurin), Groovy, and Gradle. Self-updates SDKMAN when re-run.
- `install-python.sh` — system Python 3 + pip + venv via apt.
- `install-pyenv.sh` — pyenv plus a pinned Python build.
- `install-uv.sh` — uv: fast Python package/project manager.
- `install-go.sh` — Go from the official tarball.
- `install-nodejs.sh` — Node.js via nvm (default LTS).

### Local LLMs
- `install-ollama.sh` — Ollama (CLI + systemd service).
- `install-lmstudio.sh` — LM Studio AppImage + desktop launcher.
- `install-llamacpp.sh` — llama.cpp built from source. Default backend is **Vulkan** (`BACKEND=vulkan`); also supports `cpu`, `cuda`, `hip`. The menu prompts for backend choice if llama.cpp is in the run list. Symlinks `llama-cli`/`llama-server`/etc. into `~/.local/bin`.

### Editors / dev apps
- `install-vscode.sh` — Visual Studio Code.
- `install-cursor.sh` — Cursor AI code editor (AppImage).
- `install-intellij.sh` — JetBrains IntelliJ IDEA.
- `install-micro.sh` — micro, modern terminal text editor.
- `install-fresh.sh` — Fresh terminal text editor (latest `.deb` from sinelaw/fresh GitHub release).
- `install-claude-code.sh` — Claude Code CLI (Anthropic).
- `install-opencode.sh` — opencode, open-source terminal coding agent.
- `install-little-coder.sh` — little-coder, npm-based AI coding agent CLI.
- `install-pi.sh` — pi (pi.dev), terminal coding agent (npm; depends on Node).
- `install-oh-my-pi.sh` — Oh My Pi, AI coding agent for the terminal (hash-anchored edits, LSP, Python, browser, subagents); binary `omp` from [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi).
- `install-docker-desktop.sh` — Docker Desktop.

### Productivity
- `install-obsidian.sh` — Obsidian (flatpak).
- `install-chrome.sh` — Google Chrome (`.deb`).
- `install-1password.sh` — 1Password desktop client.
- `install-gmail.sh` — Gmail web-app launcher (Chrome `--app=` mode wrapped in a `.desktop` entry).
- `install-google-calendar.sh` — Google Calendar web-app launcher (same wrapper as Gmail).
- `install-google-contacts.sh` — Google Contacts web-app launcher (same wrapper as Gmail).

### Comms
- `install-slack.sh` — Slack desktop client.
- `install-discord.sh` — Discord desktop client.
- `install-zoom.sh` — Zoom desktop client.
- `install-signal.sh` — Signal desktop client.

### Games
- `install-steam.sh` — Steam (Valve's official `.deb`; enables i386 multiarch).

### Networking
- `install-tailscale.sh` — Tailscale mesh VPN.

### Databases
- `install-postgres.sh` — PostgreSQL + `postgresql-contrib` + `pgcli`. Creates a Postgres role and DB matching your Linux user.

### Sync / utilities
- `install-syncthing.sh` — Syncthing (per-user systemd service).
- `install-vlc.sh` — VLC media player.
- `install-handbrake.sh` — HandBrake (GUI + CLI).
- `install-flameshot.sh` — Flameshot screenshot tool.

### Terminal experience
- `install-modern-cli.sh` — bundle of modern CLI tools: ripgrep, fd, bat, eza, fzf, zoxide, git-delta, jq, yq, tree, htop, ncdu. Adds aliases (`fd`, `bat`, eza as `ls`/`ll`/`la`/`lt`) and zoxide init to `~/.bashrc`.
- `install-nerd-fonts.sh` — FiraCode, JetBrainsMono, Hack, Meslo, CascadiaCode (Nerd Fonts).
- `install-starship.sh` — Starship prompt with the Gruvbox Rainbow preset; sets CaskaydiaCove Nerd Font Mono as the GNOME Terminal default font.
- `install-btop.sh` — btop process/resource monitor.
- `install-ghostty.sh` — Ghostty terminal emulator (Ubuntu archive package if available, else the classic snap). Seeds `~/.config/ghostty/config` with CaskaydiaCove Nerd Font Mono if no config exists.

### GPU monitoring
- `install-nvtop.sh` — nvtop (NVIDIA + AMD).
- `install-radeontop.sh` — radeontop (AMD).
- `install-amdgpu-top.sh` — amdgpu-top (AMD).
- `install-mission-center.sh` — Mission Center, GTK system monitor with GPU panels.

## Notes

- Scripts assume Ubuntu and use `apt-get`. They use `sudo` where needed.
- Most scripts append shell-init blocks to `~/.bashrc` (pyenv, sdkman, nvm, go, uv). Open a new shell or `source ~/.bashrc` after running.
- Pinned-version downloads (LM Studio, Go, AMD drivers) **will go stale** — check the upstream source and override the version env var when needed. `update-versions.sh` automates this for Go, nvm, Python, and Nerd Fonts; LM Studio and AMD drivers are still manual.
- `install-amd-drivers.sh` installs ROCm by default (`USECASE=graphics,rocm`). If you only want graphics, use `USECASE=graphics`.
- On a brand-new Ubuntu LTS release, `install-amd-drivers.sh` and `install-docker-desktop.sh` may fail until AMD/Docker publish packages for the new codename.
