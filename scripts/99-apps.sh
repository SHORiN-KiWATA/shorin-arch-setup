#!/bin/bash

# ==============================================================================
# 99-apps.sh - Common Applications (FZF Menu + Batch Yay + Flatpak)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

# Ensure FZF is installed
if ! command -v fzf &> /dev/null; then
    log "Installing dependency: fzf..."
    pacman -S --noconfirm fzf >/dev/null 2>&1
fi

trap 'echo -e "\n   ${H_YELLOW}>>> Operation cancelled by user (Ctrl+C). Skipping...${NC}"' INT

# ------------------------------------------------------------------------------
# 0. Identify Target User
# ------------------------------------------------------------------------------
section "Phase 5" "Common Applications"

log "Identifying target user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)

if [ -n "$DETECTED_USER" ]; then
    TARGET_USER="$DETECTED_USER"
else
    read -p "   Please enter the target username: " TARGET_USER
fi
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# ------------------------------------------------------------------------------
# 1. List Selection (FZF with Countdown)
# ------------------------------------------------------------------------------
if [ "$DESKTOP_ENV" == "kde" ]; then
    LIST_FILENAME="kde-common-applist.txt"
else
    LIST_FILENAME="common-applist.txt"
fi
LIST_FILE="$PARENT_DIR/$LIST_FILENAME"

YAY_APPS=()
FLATPAK_APPS=()
FAILED_PACKAGES=()

if [ ! -f "$LIST_FILE" ]; then
    warn "File $LIST_FILENAME not found. Skipping."
    trap - INT
    exit 0
fi

# ---------------------------------------------------------
# 1.1 Pre-process List & Countdown
# ---------------------------------------------------------

# Generate a clean list for FZF logic
# Logic:
# 1. Split line by '#'
# 2. Left part: Check prefix (flatpak:/AUR:) -> Determine Type -> Strip Prefix -> Clean Name
# 3. Right part: Clean Description
# 4. Output: "CleanName <TAB> # [Type] Description"
mapfile -t PARSED_LIST < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | awk -F'#' '{
    # $1 is package part, $2 is description part
    pkg_part = $1
    desc_part = $2
    
    # Trim whitespace
    gsub(/[ \t]+$/, "", pkg_part)
    gsub(/^[ \t]+/, "", pkg_part)
    if (desc_part != "") {
        gsub(/^[ \t]+|[ \t]+$/, "", desc_part)
    }

    # Identify Type & Strip Prefix
    if (pkg_part ~ /^flatpak:/) {
        sub(/^flatpak:/, "", pkg_part)
        type_tag = "[Flatpak]"
    } else if (pkg_part ~ /^AUR:/) {
        sub(/^AUR:/, "", pkg_part)
        type_tag = "[AUR]"
    } else {
        type_tag = "[Repo]"
    }

    # Format output for FZF
    # If description exists, append it; otherwise just show type
    if (desc_part != "") {
        printf "%s\t# %s %s\n", pkg_part, type_tag, desc_part
    } else {
        printf "%s\t# %s\n", pkg_part, type_tag
    }
}')

if [ ${#PARSED_LIST[@]} -eq 0 ]; then
    warn "App list is empty. Skipping."
    trap - INT
    exit 0
fi

echo ""
echo -e "   Selected List: ${BOLD}$LIST_FILENAME${NC}"
echo -e "   ${H_YELLOW}>>> Default installation will start in 120 seconds.${NC}"
echo -e "   ${H_CYAN}>>> Press [ANY KEY] to customize selection...${NC}"

if read -t 120 -n 1 -s -r; then
    USER_INTERVENTION=true
else
    USER_INTERVENTION=false
fi

# ---------------------------------------------------------
# 1.2 Selection Logic
# ---------------------------------------------------------
SELECTED_RAW=""

if [ "$USER_INTERVENTION" = true ]; then
    # --- Interactive FZF ---
    clear
    echo -e "\n  Loading application list..."
    
    # Using printf to feed array safely into fzf
    # Note: PARSED_LIST already contains Tabs from awk, so we don't need extra sed here
    SELECTED_RAW=$(printf "%s\n" "${PARSED_LIST[@]}" | \
        fzf --multi \
            --layout=reverse \
            --border \
            --margin=1,2 \
            --prompt="Search App > " \
            --pointer=">>" \
            --marker="* " \
            --delimiter=$'\t' \
            --with-nth=1 \
            --bind 'load:select-all' \
            --bind 'ctrl-a:select-all,ctrl-d:deselect-all' \
            --info=inline \
            --header="[TAB] TOGGLE | [ENTER] INSTALL | [CTRL-D] DE-ALL | [CTRL-A] SE-ALL" \
            --preview "echo {} | cut -f2 -d$'\t' | sed 's/^# //'" \
            --preview-window=right:45%:wrap:border-left \
            --color=dark \
            --color=fg+:white,bg+:black \
            --color=hl:blue,hl+:blue:bold \
            --color=header:yellow:bold \
            --color=info:magenta \
            --color=prompt:cyan,pointer:cyan:bold,marker:green:bold \
            --color=spinner:yellow)
    
    clear
    
    if [ -z "$SELECTED_RAW" ]; then
        log "Skipping application installation (User cancelled)."
        trap - INT
        exit 0
    fi
else
    # --- Auto Confirm (Timeout) ---
    log "Timeout reached (120s). Auto-confirming ALL applications."
    SELECTED_RAW=$(printf "%s\n" "${PARSED_LIST[@]}")
fi

# ------------------------------------------------------------------------------
# 2. Categorize Selection
# ------------------------------------------------------------------------------
log "Processing selection..."

# Loop through the raw FZF output (format: "Name <TAB> # [Type] Description")
while IFS= read -r line; do
    # Extract Name (Before TAB)
    pkg_name=$(echo "$line" | cut -f1 -d$'\t' | xargs)
    # Extract Type info (From description part, used to identify flatpak)
    # The description part looks like: "# [Flatpak] Some description"
    pkg_meta=$(echo "$line" | cut -f2 -d$'\t')
    
    [[ -z "$pkg_name" ]] && continue

    if [[ "$pkg_meta" == *"[Flatpak]"* ]]; then
        FLATPAK_APPS+=("$pkg_name")
    else
        # Both [Repo] and [AUR] go to Yay
        YAY_APPS+=("$pkg_name")
    fi
done <<< "$SELECTED_RAW"

info_kv "Scheduled" "Yay/AUR: ${#YAY_APPS[@]}" "Flatpak: ${#FLATPAK_APPS[@]}"

# ------------------------------------------------------------------------------
# 3. Install Applications
# ------------------------------------------------------------------------------

# --- A. Install Yay Apps (BATCH MODE) ---
if [ ${#YAY_APPS[@]} -gt 0 ]; then
    section "Step 1/2" "System Packages (Yay - Batch)"
    
    # 1. Filter out already installed packages
    YAY_INSTALL_QUEUE=()
    for pkg in "${YAY_APPS[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            log "Skipping '$pkg' (Already installed)."
        else
            YAY_INSTALL_QUEUE+=("$pkg")
        fi
    done

    # 2. Execute Batch Install if queue is not empty
    if [ ${#YAY_INSTALL_QUEUE[@]} -gt 0 ]; then
        # Configure NOPASSWD for seamless batch install
        SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_apps"
        echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
        chmod 440 "$SUDO_TEMP_FILE"
        
        BATCH_LIST="${YAY_INSTALL_QUEUE[*]}"
        info_kv "Installing" "${#YAY_INSTALL_QUEUE[@]} packages via Yay"
        
        # Run Yay Batch
        if ! exe runuser -u "$TARGET_USER" -- yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
            error "Yay batch installation failed."
            # Since it's batch, if it fails, we mark the whole queue as potentially failed
            for pkg in "${YAY_INSTALL_QUEUE[@]}"; do
                FAILED_PACKAGES+=("yay-batch-fail:$pkg")
            done
        else
            success "Yay batch installation completed."
        fi
        
        rm -f "$SUDO_TEMP_FILE"
    else
        log "All Yay packages are already installed."
    fi
fi

# --- B. Install Flatpak Apps (INDIVIDUAL MODE) ---
if [ ${#FLATPAK_APPS[@]} -gt 0 ]; then
    section "Step 2/2" "Flatpak Packages (Individual)"
    
    for app in "${FLATPAK_APPS[@]}"; do
        # 1. Check if installed
        if flatpak info "$app" &>/dev/null; then
            log "Skipping '$app' (Already installed)."
            continue
        fi

        # 2. Install Individually
        log "Installing Flatpak: $app ..."
        if ! exe flatpak install -y flathub "$app"; then
            error "Failed to install: $app"
            FAILED_PACKAGES+=("flatpak:$app")
        else
            success "Installed $app"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 3.5 Generate Failure Report
# ------------------------------------------------------------------------------
if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
    DOCS_DIR="$HOME_DIR/Documents"
    REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"
    
    if [ ! -d "$DOCS_DIR" ]; then runuser -u "$TARGET_USER" -- mkdir -p "$DOCS_DIR"; fi
    
    # Append to report
    echo -e "\n--- Phase 5 (Common Apps - $DESKTOP_ENV) Failures [$(date)] ---" >> "$REPORT_FILE"
    printf "%s\n" "${FAILED_PACKAGES[@]}" >> "$REPORT_FILE"
    chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
    
    warn "Some applications failed to install. List saved to:"
    echo -e "   ${BOLD}$REPORT_FILE${NC}"
else
    success "All scheduled applications processed."
fi

# ------------------------------------------------------------------------------
# 4. Steam Locale Fix
# ------------------------------------------------------------------------------
section "Post-Install" "Game Environment Tweaks"

STEAM_desktop_modified=false

# Method 1: Native Steam
NATIVE_DESKTOP="/usr/share/applications/steam.desktop"
if [ -f "$NATIVE_DESKTOP" ]; then
    log "Checking Native Steam..."
    if ! grep -q "env LANG=zh_CN.UTF-8" "$NATIVE_DESKTOP"; then
        exe sed -i 's|^Exec=/usr/bin/steam|Exec=env LANG=zh_CN.UTF-8 /usr/bin/steam|' "$NATIVE_DESKTOP"
        exe sed -i 's|^Exec=steam|Exec=env LANG=zh_CN.UTF-8 steam|' "$NATIVE_DESKTOP"
        success "Patched Native Steam .desktop."
        STEAM_desktop_modified=true
    else
        log "Native Steam already patched."
    fi
fi

if [ "$STEAM_desktop_modified" = false ]; then
    log "Steam not found or already configured. Skipping fix."
fi

# Reset Trap
trap - INT

log "Module 99-apps completed."