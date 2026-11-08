#!/bin/bash
# Interactive install menu — pure-bash TUI with a collapsible category tree,
# arrow-key navigation, checkboxes, and select/deselect-all (global +
# per-category). Press `r` to view README.md from inside the menu.
# No external dependencies beyond bash + tput + ANSI.
#
# Each sub-script has its own `set -e`, so a failed script aborts itself
# before causing harm — we record it and move on.

ITEMS=(
    "Setup|./update-versions.sh"

    "Drivers / base|./install-flatpak.sh"
    "Drivers / base|./install-amd-drivers.sh"

    "Git/GitHub|./install-git-config.sh"
    "Git/GitHub|./install-gh.sh"

    "Languages|./install-sdkman.sh"
    "Languages|./install-python.sh"
    "Languages|./install-pyenv.sh"
    "Languages|./install-uv.sh"
    "Languages|./install-go.sh"
    "Languages|./install-nodejs.sh"

    "Local LLMs|./install-ollama.sh"
    "Local LLMs|./install-lmstudio.sh"
    "Local LLMs|./install-llamacpp.sh"
    "Local LLMs|./install-comfyui.sh"

    "Editors / dev apps|./install-vscode.sh"
    "Editors / dev apps|./install-cursor.sh"
    "Editors / dev apps|./install-intellij.sh"
    "Editors / dev apps|./install-micro.sh"
    "Editors / dev apps|./install-fresh.sh"
    "Editors / dev apps|./install-claude-code.sh"
    "Editors / dev apps|./install-claude-desktop.sh"
    "Editors / dev apps|./install-opencode.sh"
    "Editors / dev apps|./install-little-coder.sh"
    "Editors / dev apps|./install-pi.sh"
    "Editors / dev apps|./install-oh-my-pi.sh"
    "Editors / dev apps|./install-docker-desktop.sh"

    "Productivity|./install-obsidian.sh"
    "Productivity|./install-chrome.sh"
    "Productivity|./install-1password.sh"
    "Productivity|./install-gmail.sh"
    "Productivity|./install-google-calendar.sh"
    "Productivity|./install-google-contacts.sh"

    "Comms|./install-slack.sh"
    "Comms|./install-discord.sh"
    "Comms|./install-zoom.sh"
    "Comms|./install-signal.sh"

    "Games|./install-steam.sh"

    "Networking|./install-tailscale.sh"
    "Networking|./install-rdp-server.sh"
    "Networking|./install-nas-tools.sh"
    "Networking|./install-avahi.sh"

    "Databases|./install-postgres.sh"

    "Sync / utilities|./install-syncthing.sh"
    "Sync / utilities|./install-unison.sh"
    "Sync / utilities|./install-vlc.sh"
    "Sync / utilities|./install-handbrake.sh"
    "Sync / utilities|./install-flameshot.sh"

    "Terminal experience|./install-modern-cli.sh"
    "Terminal experience|./install-nerd-fonts.sh"
    "Terminal experience|./install-starship.sh"
    "Terminal experience|./install-btop.sh"
    "Terminal experience|./install-ghostty.sh"

    "GPU monitoring|./install-nvtop.sh"
    "GPU monitoring|./install-radeontop.sh"
    "GPU monitoring|./install-amdgpu-top.sh"
    "GPU monitoring|./install-mission-center.sh"
)

# --- Build state (parallel arrays) ---

CAT_NAMES=()        # [cat_idx] = "Category Name"
CAT_EXPANDED=()     # [cat_idx] = 0|1 (default 1)
CAT_ITEM_IDXS=()    # [cat_idx] = "fi1 fi2 fi3"

PATHS=()
ITEM_NAMES=()
ITEM_CATS=()
ITEM_SEL=()

for entry in "${ITEMS[@]}"; do
    cat="${entry%%|*}"
    path="${entry#*|}"

    cat_idx=-1
    for ((i = 0; i < ${#CAT_NAMES[@]}; i++)); do
        if [ "${CAT_NAMES[$i]}" = "$cat" ]; then cat_idx=$i; break; fi
    done
    if [ $cat_idx -lt 0 ]; then
        cat_idx=${#CAT_NAMES[@]}
        CAT_NAMES+=("$cat")
        CAT_EXPANDED+=(1)
        CAT_ITEM_IDXS+=("")
    fi

    flat_idx=${#PATHS[@]}
    PATHS+=("$path")
    ITEM_NAMES+=("$(basename "$path")")
    ITEM_CATS+=("$cat_idx")
    ITEM_SEL+=(1)

    if [ -z "${CAT_ITEM_IDXS[$cat_idx]}" ]; then
        CAT_ITEM_IDXS[$cat_idx]="$flat_idx"
    else
        CAT_ITEM_IDXS[$cat_idx]="${CAT_ITEM_IDXS[$cat_idx]} $flat_idx"
    fi
done

# A couple of scripts default to off:
#   install-amd-drivers.sh — Ubuntu 26 ships modern amdgpu in-kernel, so it's
#     only useful for ROCm builds.
#   install-comfyui.sh — pulls several GB of PyTorch wheels; opt in when you
#     actually want image generation on this box.
for ((i = 0; i < ${#PATHS[@]}; i++)); do
    case "${PATHS[$i]}" in
        ./install-amd-drivers.sh|./install-comfyui.sh) ITEM_SEL[$i]=0 ;;
    esac
done

NUM_ITEMS=${#PATHS[@]}
NUM_CATS=${#CAT_NAMES[@]}

VISIBLE_ROWS=()    # entries: "C:catidx" | "I:flatidx"
CURSOR=0
WINDOW_TOP=0

build_visible_rows() {
    VISIBLE_ROWS=()
    local ci fi
    for ((ci = 0; ci < NUM_CATS; ci++)); do
        VISIBLE_ROWS+=("C:$ci")
        if [ "${CAT_EXPANDED[$ci]}" = "1" ]; then
            for fi in ${CAT_ITEM_IDXS[$ci]}; do
                VISIBLE_ROWS+=("I:$fi")
            done
        fi
    done
}

# --- Terminal setup ---

cleanup() { printf '\033[?25h\033[?7h'; stty "$STTY_SAVED" 2>/dev/null; }
STTY_SAVED="$(stty -g 2>/dev/null || echo)"
trap cleanup EXIT INT TERM
printf '\033[?25l'   # hide cursor

# --- Render ---

cat_counts() {
    local cat_idx="$1" cs=0 ct=0 fi
    for fi in ${CAT_ITEM_IDXS[$cat_idx]}; do
        ct=$((ct + 1))
        [ "${ITEM_SEL[$fi]}" = "1" ] && cs=$((cs + 1))
    done
    printf '%d %d' "$cs" "$ct"
}

calc_window() {
    local term_lines
    term_lines="$(tput lines 2>/dev/null || echo 40)"
    # 5 banner + 1 blank + 1 status + 1 blank = 8 above; 1 blank + 3 footer = 4 below
    WINDOW_HEIGHT=$((term_lines - 12))
    [ "$WINDOW_HEIGHT" -lt 5 ] && WINDOW_HEIGHT=5

    if [ "$CURSOR" -lt "$WINDOW_TOP" ]; then
        WINDOW_TOP=$CURSOR
    elif [ "$CURSOR" -ge $((WINDOW_TOP + WINDOW_HEIGHT)) ]; then
        WINDOW_TOP=$((CURSOR - WINDOW_HEIGHT + 1))
    fi
    [ "$WINDOW_TOP" -lt 0 ] && WINDOW_TOP=0
    local max_top=$((${#VISIBLE_ROWS[@]} - WINDOW_HEIGHT))
    [ "$max_top" -lt 0 ] && max_top=0
    [ "$WINDOW_TOP" -gt "$max_top" ] && WINDOW_TOP=$max_top
}

render() {
    build_visible_rows
    if [ "$CURSOR" -ge "${#VISIBLE_ROWS[@]}" ]; then
        CURSOR=$((${#VISIBLE_ROWS[@]} - 1))
    fi
    [ "$CURSOR" -lt 0 ] && CURSOR=0
    calc_window

    printf '\033[H'

    # Banner.
    printf '\033[36m\033[K\n'
    printf '%s\033[K\n' "       _                 _               _           _        _ _"
    printf '%s\033[K\n' " _   _| |__  _   _ _ __ | |_ _   _      (_)_ __  ___| |_ __ _| | |"
    printf '%s\033[K\n' "| | | | '_ \\| | | | '_ \\| __| | | |_____| | '_ \\/ __| __/ _\` | | |"
    printf '%s\033[K\n' "| |_| | |_) | |_| | | | | |_| |_| |_____| | | | \\__ \\ || (_| | | |"
    printf '%s\033[K\n' " \\__,_|_.__/ \\__,_|_| |_|\\__|\\__,_|     |_|_| |_|___/\\__\\__,_|_|_|"
    printf '\033[0m\033[K\n'

    # Status.
    local sel_total=0 fi
    for ((fi = 0; fi < NUM_ITEMS; fi++)); do
        [ "${ITEM_SEL[$fi]}" = "1" ] && sel_total=$((sel_total + 1))
    done
    printf '  \033[1mSelected: %d/%d\033[0m\033[K\n\033[K\n' "$sel_total" "$NUM_ITEMS"

    # Visible rows window.
    local end=$((WINDOW_TOP + WINDOW_HEIGHT))
    [ "$end" -gt "${#VISIBLE_ROWS[@]}" ] && end=${#VISIBLE_ROWS[@]}

    local r vr kind idx hl reset
    for ((r = WINDOW_TOP; r < end; r++)); do
        vr="${VISIBLE_ROWS[$r]}"
        kind="${vr%%:*}"
        idx="${vr#*:}"
        if [ "$r" -eq "$CURSOR" ]; then
            hl=$'\033[7m'; reset=$'\033[27m'
        else
            hl=""; reset=""
        fi
        if [ "$kind" = "C" ]; then
            local marker counts cs ct
            if [ "${CAT_EXPANDED[$idx]}" = "1" ]; then marker="▼"; else marker="▶"; fi
            counts="$(cat_counts "$idx")"
            cs="${counts%% *}"; ct="${counts##* }"
            printf '%s\033[36m%s %s\033[0m\033[2m (%d/%d)\033[0m%s\033[K\n' \
                "$hl" "$marker" "${CAT_NAMES[$idx]}" "$cs" "$ct" "$reset"
        else
            local box
            if [ "${ITEM_SEL[$idx]}" = "1" ]; then box="\033[32m[x]\033[0m"; else box="[ ]"; fi
            printf "%s    %b %s%s\033[K\n" "$hl" "$box" "${ITEM_NAMES[$idx]}" "$reset"
        fi
    done

    local rendered=$((end - WINDOW_TOP))
    while [ "$rendered" -lt "$WINDOW_HEIGHT" ]; do
        printf '\033[K\n'
        rendered=$((rendered + 1))
    done

    # Footer.
    printf '\033[K\n'
    printf '  \033[2m↑↓ move · space toggle · ←→ collapse/expand · r README · c config\033[0m\033[K\n'
    printf '  \033[2ma/d select/deselect all · A/D current category · g run · q quit\033[0m\033[K\n'

    printf '\033[J'
}

# --- Input ---

read_key() {
    local c rest
    IFS= read -rsn1 c
    if [ "$c" = $'\e' ]; then
        IFS= read -rsn2 rest
        case "$rest" in
            "[A") echo up ;;
            "[B") echo down ;;
            "[C") echo right ;;
            "[D") echo left ;;
            *)    echo escape ;;
        esac
        return
    fi
    case "$c" in
        ""|$'\n'|$'\r') echo enter ;;
        " ") echo space ;;
        a) echo a ;;
        d) echo d ;;
        A) echo A ;;
        D) echo D ;;
        g) echo go ;;
        q) echo quit ;;
        r|R) echo readme ;;
        c|C) echo config ;;
        \?) echo help ;;
        *) echo "x" ;;
    esac
}

view_readme() {
    local readme_path
    readme_path="$(dirname "$0")/README.md"
    [ -f "$readme_path" ] || return
    printf '\033[?25h\033[2J\033[H'
    if command -v glow >/dev/null 2>&1; then
        glow -p "$readme_path"
    elif command -v bat >/dev/null 2>&1; then
        bat --paging=always --language=md "$readme_path"
    else
        less "$readme_path"
    fi
    printf '\033[?25l\033[2J'
}

# --- Bootstrap configuration panel ---
#
# Shows the values bootstrap.sh wrote to the system (git identity, SSH key,
# origin URL, clone dir) and lets you edit name/email/origin in place. SSH
# key and clone dir are display-only; changing them post-bootstrap is rarely
# what you actually want.

CFG_LABELS=("Git user name" "Git user email" "SSH key" "Repo URL" "Clone dir" "Render backend")
CFG_EDITABLE=(1 1 0 1 0 1)
CFG_CURSOR=0

# llama.cpp backend; respect env override, default vulkan.
BACKEND_CHOICE="${BACKEND:-vulkan}"

cfg_value() {
    case "$1" in
        0) git config --global user.name 2>/dev/null || echo "(unset)" ;;
        1) git config --global user.email 2>/dev/null || echo "(unset)" ;;
        2)
            local key="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
            if [ -f "$key" ]; then
                local fp
                fp="$(ssh-keygen -lf "$key" 2>/dev/null | awk '{print $2}')"
                printf '%s  (%s)' "$key" "$fp"
            else
                printf '(missing) %s' "$key"
            fi
            ;;
        3) git -C "$(dirname "$0")" remote get-url origin 2>/dev/null || echo "(no remote)" ;;
        4) (cd "$(dirname "$0")" && pwd) ;;
        5) printf '%s   \033[2m(used by install-llamacpp.sh)\033[0m' "$BACKEND_CHOICE" ;;
    esac
}

render_config() {
    printf '\033[H'

    # Banner.
    printf '\033[36m\033[K\n'
    printf '%s\033[K\n' "       _                 _               _           _        _ _"
    printf '%s\033[K\n' " _   _| |__  _   _ _ __ | |_ _   _      (_)_ __  ___| |_ __ _| | |"
    printf '%s\033[K\n' "| | | | '_ \\| | | | '_ \\| __| | | |_____| | '_ \\/ __| __/ _\` | | |"
    printf '%s\033[K\n' "| |_| | |_) | |_| | | | | |_| |_| |_____| | | | \\__ \\ || (_| | | |"
    printf '%s\033[K\n' " \\__,_|_.__/ \\__,_|_| |_|\\__|\\__,_|     |_|_| |_|___/\\__\\__,_|_|_|"
    printf '\033[0m\033[K\n'

    printf '  \033[1mConfiguration\033[0m\033[K\n'
    printf '  \033[2m(values pulled from system state; render backend feeds install-llamacpp.sh)\033[0m\033[K\n\033[K\n'

    local i hl reset edit_marker
    for ((i = 0; i < ${#CFG_LABELS[@]}; i++)); do
        if [ "$i" -eq "$CFG_CURSOR" ]; then
            hl=$'\033[7m'; reset=$'\033[27m'
        else
            hl=""; reset=""
        fi
        edit_marker=""
        [ "${CFG_EDITABLE[$i]}" = "1" ] && edit_marker='  \033[2m[edit]\033[0m'
        printf "%s  %-18s %s%b%s\033[K\n" \
            "$hl" "${CFG_LABELS[$i]}:" "$(cfg_value "$i")" "$edit_marker" "$reset"
    done

    local term_lines pad
    term_lines="$(tput lines 2>/dev/null || echo 40)"
    pad=$((term_lines - 8 - 3 - ${#CFG_LABELS[@]} - 4))
    [ "$pad" -lt 0 ] && pad=0
    while [ "$pad" -gt 0 ]; do printf '\033[K\n'; pad=$((pad - 1)); done

    printf '\033[K\n'
    printf '  \033[2m↑↓ select · enter edit · esc / q back to menu\033[0m\033[K\n'
    printf '\033[J'
}

edit_cfg_field() {
    local idx=$CFG_CURSOR
    [ "${CFG_EDITABLE[$idx]}" = "1" ] || return

    cleanup
    printf '\033[?25h\033[2J\033[H'

    local current new
    case "$idx" in
        0)
            current="$(cfg_value 0)"
            echo "Current git user name: $current"
            read -r -p "New value (empty to keep): " new < /dev/tty || new=""
            [ -n "$new" ] && git config --global user.name "$new"
            ;;
        1)
            current="$(cfg_value 1)"
            echo "Current git user email: $current"
            read -r -p "New value (empty to keep): " new < /dev/tty || new=""
            [ -n "$new" ] && git config --global user.email "$new"
            ;;
        3)
            current="$(cfg_value 3)"
            echo "Current origin URL: $current"
            read -r -p "New value (empty to keep): " new < /dev/tty || new=""
            [ -n "$new" ] && git -C "$(dirname "$0")" remote set-url origin "$new"
            ;;
        5)
            echo "Current render backend: $BACKEND_CHOICE"
            echo "  1) vulkan  — cross-vendor GPU (Intel/AMD/NVIDIA)"
            echo "  2) cpu     — CPU only"
            echo "  3) cuda    — NVIDIA (requires CUDA toolkit)"
            echo "  4) hip     — AMD ROCm"
            read -r -p "Choose [1-4, empty to keep]: " new < /dev/tty || new=""
            case "$new" in
                1) BACKEND_CHOICE=vulkan ;;
                2) BACKEND_CHOICE=cpu ;;
                3) BACKEND_CHOICE=cuda ;;
                4) BACKEND_CHOICE=hip ;;
            esac
            ;;
    esac

    printf '\033[?25l\033[2J'
}

view_config() {
    CFG_CURSOR=0
    while true; do
        render_config
        local key; key="$(read_key)"
        case "$key" in
            up)   CFG_CURSOR=$((CFG_CURSOR - 1)); [ "$CFG_CURSOR" -lt 0 ] && CFG_CURSOR=0 ;;
            down) CFG_CURSOR=$((CFG_CURSOR + 1)); [ "$CFG_CURSOR" -ge "${#CFG_LABELS[@]}" ] && CFG_CURSOR=$((${#CFG_LABELS[@]} - 1)) ;;
            enter|space) edit_cfg_field ;;
            quit|escape) printf '\033[2J'; break ;;
            *) ;;
        esac
    done
}

# --- Actions ---

cur_kind_idx() {
    local vr="${VISIBLE_ROWS[$CURSOR]}"
    echo "${vr%%:*} ${vr#*:}"
}

toggle_under_cursor() {
    read kind idx <<< "$(cur_kind_idx)"
    if [ "$kind" = "I" ]; then
        if [ "${ITEM_SEL[$idx]}" = "1" ]; then ITEM_SEL[$idx]=0; else ITEM_SEL[$idx]=1; fi
    else
        if [ "${CAT_EXPANDED[$idx]}" = "1" ]; then CAT_EXPANDED[$idx]=0; else CAT_EXPANDED[$idx]=1; fi
    fi
}

collapse_left() {
    read kind idx <<< "$(cur_kind_idx)"
    if [ "$kind" = "C" ]; then
        CAT_EXPANDED[$idx]=0
    else
        local cat_idx="${ITEM_CATS[$idx]}"
        CAT_EXPANDED[$cat_idx]=0
        build_visible_rows
        local r=0 vr
        for vr in "${VISIBLE_ROWS[@]}"; do
            if [ "$vr" = "C:$cat_idx" ]; then CURSOR=$r; break; fi
            r=$((r + 1))
        done
    fi
}

expand_right() {
    read kind idx <<< "$(cur_kind_idx)"
    if [ "$kind" = "C" ]; then
        CAT_EXPANDED[$idx]=1
    fi
}

set_all() {
    local val=$1 fi
    for ((fi = 0; fi < NUM_ITEMS; fi++)); do ITEM_SEL[$fi]=$val; done
}

set_current_category() {
    local val=$1 cat_idx fi
    read kind idx <<< "$(cur_kind_idx)"
    if [ "$kind" = "C" ]; then cat_idx=$idx; else cat_idx="${ITEM_CATS[$idx]}"; fi
    for fi in ${CAT_ITEM_IDXS[$cat_idx]}; do ITEM_SEL[$fi]=$val; done
}

# --- Main loop ---

build_visible_rows
printf '\033[2J'   # one-time full clear at start

while true; do
    render
    key="$(read_key)"
    case "$key" in
        up)    CURSOR=$((CURSOR - 1)); [ "$CURSOR" -lt 0 ] && CURSOR=0 ;;
        down)  CURSOR=$((CURSOR + 1)) ;;
        left)  collapse_left ;;
        right) expand_right ;;
        space|enter) toggle_under_cursor ;;
        a) set_all 1 ;;
        d) set_all 0 ;;
        A) set_current_category 1 ;;
        D) set_current_category 0 ;;
        readme) view_readme ;;
        config) view_config ;;
        go) break ;;
        quit) printf '\033[2J\033[H'; echo "Cancelled."; exit 0 ;;
        *) ;;
    esac
done

# --- Build run list ---

cleanup
printf '\033[2J\033[H'

SCRIPTS=()
for ((fi = 0; fi < NUM_ITEMS; fi++)); do
    [ "${ITEM_SEL[$fi]}" = "1" ] && SCRIPTS+=("${PATHS[$fi]}")
done

if [ "${#SCRIPTS[@]}" -eq 0 ]; then
    echo "Nothing selected. Exiting."
    exit 0
fi

# Render backend was selected in the config panel (default vulkan).
export BACKEND="$BACKEND_CHOICE"

# --- Run loop ---

if [ -t 1 ]; then
    C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'
else
    C_BOLD=""; C_DIM=""; C_GREEN=""; C_RED=""; C_RESET=""
fi

SUCCEEDED=()
FAILED=()
SKIPPED=()
LOG_DIR="$(mktemp -d -t ubuntu-install.XXXXXX)"

echo
echo "${C_DIM}Logs: $LOG_DIR${C_RESET}"
echo "Running ${#SCRIPTS[@]} scripts..."
echo

for script in "${SCRIPTS[@]}"; do
    name="$(basename "$script")"
    if [ ! -x "$script" ]; then
        printf '  ? %-32s (not executable, skipped)\n' "$name"
        SKIPPED+=("$script")
        continue
    fi
    printf '%s→ %s%s\n' "$C_BOLD" "$name" "$C_RESET"
    log_file="$LOG_DIR/${name}.log"
    "$script" 2>&1 | tee "$log_file"
    rc=${PIPESTATUS[0]}
    if [ "$rc" -eq 0 ]; then
        SUCCEEDED+=("$script")
        printf '  %s✓ %s%s\n' "$C_GREEN" "$name" "$C_RESET"
    else
        FAILED+=("$script")
        printf '  %s✗ %s (exit %d) — see %s%s\n' "$C_RED" "$name" "$rc" "$log_file" "$C_RESET"
    fi
    echo
done

echo "============================================================"
echo "  Summary"
echo "============================================================"
printf '  Succeeded: %d\n' "${#SUCCEEDED[@]}"
printf '  Failed:    %d\n' "${#FAILED[@]}"
printf '  Skipped:   %d\n' "${#SKIPPED[@]}"
echo

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "Failed scripts:"
    for s in "${FAILED[@]}"; do
        echo "  - $s   (log: $LOG_DIR/$(basename "$s").log)"
    done
    echo
fi

if [ "${#SKIPPED[@]}" -gt 0 ]; then
    echo "Skipped (not executable):"
    for s in "${SKIPPED[@]}"; do
        echo "  - $s"
    done
    echo
fi

[ "${#FAILED[@]}" -eq 0 ]
