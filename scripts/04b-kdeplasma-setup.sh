#!/bin/bash

# ==============================================================================
# 06-kdeplasma-setup.sh - KDE Plasma Setup (FZF Menu + Robust Installation)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}

check_root

# Ensure FZF is installed
if ! command -v fzf &> /dev/null; then
    log "Installing dependency: fzf..."
    pacman -S --noconfirm fzf >/dev/null 2>&1
fi

trap 'echo -e "\n   ${H_YELLOW}>>> Operation cancelled by user (Ctrl+C). Skipping...${NC}"' INT

section "Phase 6" "KDE Plasma Environment"

# ------------------------------------------------------------------------------
# 0. Identify Target User
# ------------------------------------------------------------------------------
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
if [ -n "$DETECTED_USER" ]; then TARGET_USER="$DETECTED_USER"; else read -p "Target user: " TARGET_USER; fi
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# ------------------------------------------------------------------------------
# 1. Install KDE Plasma Base
# ------------------------------------------------------------------------------
section "Step 1/5" "Plasma Core"

log "Installing KDE Plasma Meta & Apps..."
KDE_PKGS="plasma-meta konsole dolphin kate firefox qt6-multimedia-ffmpeg pipewire-jack sddm"
exe pacman -S --noconfirm --needed $KDE_PKGS
success "KDE Plasma installed."

# ------------------------------------------------------------------------------
# 2. Software Store & Network (Smart Mirror Selection)
# ------------------------------------------------------------------------------
section "Step 2/5" "Software Store & Network"

log "Configuring Discover & Flatpak..."

exe pacman -S --noconfirm --needed flatpak flatpak-kcm
exe flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# --- Network Detection Logic ---
CURRENT_TZ=$(readlink -f /etc/localtime)
IS_CN_ENV=false

if [[ "$CURRENT_TZ" == *"Shanghai"* ]]; then
    IS_CN_ENV=true
    info_kv "Region" "China (Timezone)"
elif [ "$CN_MIRROR" == "1" ]; then
    IS_CN_ENV=true
    info_kv "Region" "China (Manual Env)"
elif [ "$DEBUG" == "1" ]; then
    IS_CN_ENV=true
    warn "DEBUG MODE: Forcing China Environment"
fi

# --- Mirror Configuration ---
if [ "$IS_CN_ENV" = true ]; then
    log "Enabling China Optimizations..."
    select_flathub_mirror
    success "Optimizations Enabled."
else
    log "Using Global Official Sources."
fi

# NOPASSWD for yay
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

# ------------------------------------------------------------------------------
# 3. Install Dependencies (FZF Selection + Retry Logic)
# ------------------------------------------------------------------------------
section "Step 3/5" "KDE Dependencies"

LIST_FILE="$PARENT_DIR/kde-applist.txt"
UNDO_SCRIPT="$PARENT_DIR/undochange.sh"

# --- Critical Failure Handler ---
critical_failure_handler() {
    local failed_pkg="$1"
    
    # Disable trap to prevent loops
    trap - ERR
    
    echo ""
    echo -e "\033[0;31m################################################################\033[0m"
    echo -e "\033[0;31m#                                                              #\033[0m"
    echo -e "\033[0;31m#   CRITICAL INSTALLATION FAILURE DETECTED                     #\033[0m"
    echo -e "\033[0;31m#   Package: $failed_pkg                                       #\033[0m"
    echo -e "\033[0;31m#   Status: Package not found after install attempt.           #\033[0m"
    echo -e "\033[0;31m#                                                              #\033[0m"
    echo -e "\033[0;31m#   Would you like to restore snapshot (undo changes)?         #\033[0m"
    echo -e "\033[0;31m################################################################\033[0m"
    echo ""

    while true; do
        read -p "Execute System Recovery? [y/n]: " -r choice
        case "$choice" in 
            [yY][eE][sS]|[yY]) 
                if [ -f "$UNDO_SCRIPT" ]; then
                    warn "Executing recovery script: $UNDO_SCRIPT"
                    bash "$UNDO_SCRIPT"
                    exit 1
                else
                    error "Recovery script not found at: $UNDO_SCRIPT"
                    exit 1
                fi
                ;;
            [nN][oO]|[nN])
                warn "User chose NOT to recover. System might be in a broken state."
                error "Installation aborted due to failure in: $failed_pkg"
                exit 1
                ;;
            *)
                echo -e "\033[1;33mInvalid input. Please enter 'y' to recover or 'n' to abort.\033[0m"
                ;;
        esac
    done
}

# --- Verification Function ---
verify_installation() {
    local pkg="$1"
    if pacman -Q "$pkg" &>/dev/null; then return 0; else return 1; fi
}

if [ -f "$LIST_FILE" ]; then
    
    REPO_APPS=()
    AUR_APPS=()

    # ---------------------------------------------------------
    # 3.1 Countdown Logic
    # ---------------------------------------------------------
    if ! grep -q -vE "^\s*#|^\s*$" "$LIST_FILE"; then
        warn "App list is empty. Skipping."
    else
        echo ""
        echo -e "   Selected List: ${BOLD}$LIST_FILE${NC}"
        echo -e "   ${H_YELLOW}>>> Default installation will start in 60 seconds.${NC}"
        echo -e "   ${H_RED}${BOLD}>>> WARNING: AUR packages may fail due to unstable network connection!${NC}"
        echo -e "   ${H_CYAN}>>> Press ANY KEY to customize selection...${NC}"

        if read -t 60 -n 1 -s -r; then
            USER_INTERVENTION=true
        else
            USER_INTERVENTION=false
        fi

        # ---------------------------------------------------------
        # 3.2 FZF Selection Logic
        # ---------------------------------------------------------
        SELECTED_RAW=""

        if [ "$USER_INTERVENTION" = true ]; then
            clear
            echo -e "\n  Loading package list..."

            # Visual: Name <TAB> # Description
            SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | \
                sed -E 's/[[:space:]]+#/\t#/' | \
                fzf --multi \
                    --layout=reverse \
                    --border \
                    --margin=1,2 \
                    --prompt="Search Pkg > " \
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
                warn "User cancelled selection. Skipping Step 3."
                # Empty arrays
            fi
        else
            log "Timeout reached (60s). Auto-confirming ALL packages."
            # Simulate FZF output for consistent processing
            SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed -E 's/[[:space:]]+#/\t#/')
        fi

        # ---------------------------------------------------------
        # 3.3 Categorize Selection
        # ---------------------------------------------------------
        if [ -n "$SELECTED_RAW" ]; then
            log "Processing selection..."
            while IFS= read -r line; do
                # Extract Name (Before TAB)
                raw_pkg=$(echo "$line" | cut -f1 -d$'\t' | xargs)
                [[ -z "$raw_pkg" ]] && continue
                
                # Legacy compatibility (imagemagick)
                [ "$raw_pkg" == "imagemagic" ] && raw_pkg="imagemagick"

                # Identify AUR vs Repo
                if [[ "$raw_pkg" == AUR:* ]]; then
                    clean_name="${raw_pkg#AUR:}"
                    AUR_APPS+=("$clean_name")
                elif [[ "$raw_pkg" == *"-git" ]]; then
                    # Implicit AUR if ending in -git (Legacy logic support)
                    AUR_APPS+=("$raw_pkg")
                else
                    REPO_APPS+=("$raw_pkg")
                fi
            done <<< "$SELECTED_RAW"
        fi
    fi

    info_kv "Scheduled" "Repo: ${#REPO_APPS[@]}" "AUR: ${#AUR_APPS[@]}"

    # ---------------------------------------------------------
    # 3.4 Install Applications
    # ---------------------------------------------------------

    # --- A. Install Repo Apps (BATCH MODE) ---
    if [ ${#REPO_APPS[@]} -gt 0 ]; then
        log "Phase 1: Batch Installing Repository Packages..."
        
        # Filter installed
        REPO_QUEUE=()
        for pkg in "${REPO_APPS[@]}"; do
            if ! pacman -Qi "$pkg" &>/dev/null; then
                REPO_QUEUE+=("$pkg")
            fi
        done

        if [ ${#REPO_QUEUE[@]} -gt 0 ]; then
            # Batch Install
            exe runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "${REPO_QUEUE[@]}"
            
            # Verify Loop
            log "Verifying batch installation..."
            for pkg in "${REPO_QUEUE[@]}"; do
                if ! verify_installation "$pkg"; then
                    warn "Verification failed for '$pkg'. Retrying individually..."
                    exe runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed "$pkg"
                    
                    if ! verify_installation "$pkg"; then
                        critical_failure_handler "$pkg (Repo)"
                    else
                        success "Verified: $pkg"
                    fi
                fi
            done
            success "Batch phase verified."
        else
            log "All selected repo packages are already installed."
        fi
    fi

    # --- B. Install AUR Apps (SEQUENTIAL + RETRY) ---
    if [ ${#AUR_APPS[@]} -gt 0 ]; then
        log "Phase 2: Installing AUR Packages (Sequential)..."
        log "Hint: Use Ctrl+C to skip a specific package download step."

        for aur_pkg in "${AUR_APPS[@]}"; do
            if pacman -Qi "$aur_pkg" &>/dev/null; then
                log "Skipping '$aur_pkg' (Already installed)."
                continue
            fi
            
            log "Installing AUR: $aur_pkg ..."
            install_success=false
            max_retries=2
            
            for (( i=0; i<=max_retries; i++ )); do
                if [ $i -gt 0 ]; then
                    warn "Retry $i/$max_retries for '$aur_pkg' in 3 seconds..."
                    sleep 3
                fi
                
                runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$aur_pkg"
                EXIT_CODE=$?

                # Handle Ctrl+C skip
                if [ $EXIT_CODE -eq 130 ]; then
                    warn "Skipped '$aur_pkg' by user request (Ctrl+C)."
                    break # Skip retries for this package
                fi

                if verify_installation "$aur_pkg"; then
                    install_success=true
                    success "Installed $aur_pkg"
                    break
                else
                    warn "Attempt $((i+1)) failed for $aur_pkg"
                fi
            done

            if [ "$install_success" = false ] && [ $EXIT_CODE -ne 130 ]; then
                # Trigger critical failure if not skipped by user
                critical_failure_handler "$aur_pkg (AUR)"
            fi
        done
    fi

else
    warn "kde-applist.txt not found."
fi

# ------------------------------------------------------------------------------
# 4. Dotfiles Deployment
# ------------------------------------------------------------------------------
section "Step 4/5" "KDE Config Deployment"

DOTFILES_SOURCE="$PARENT_DIR/kde-dotfiles"

if [ -d "$DOTFILES_SOURCE" ]; then
    log "Deploying KDE configurations..."
    
    # 1. Backup Existing .config
    BACKUP_NAME="config_backup_kde_$(date +%s).tar.gz"
    if [ -d "$HOME_DIR/.config" ]; then
        log "Backing up ~/.config to $BACKUP_NAME..."
        exe runuser -u "$TARGET_USER" -- tar -czf "$HOME_DIR/$BACKUP_NAME" -C "$HOME_DIR" .config
    fi
    
    # 2. Explicitly Copy .config and .local
    
    # --- Process .config ---
    if [ -d "$DOTFILES_SOURCE/.config" ]; then
        log "Merging .config..."
        if [ ! -d "$HOME_DIR/.config" ]; then mkdir -p "$HOME_DIR/.config"; fi
        
        exe cp -rf "$DOTFILES_SOURCE/.config/"* "$HOME_DIR/.config/" 2>/dev/null || true
        exe cp -rf "$DOTFILES_SOURCE/.config/." "$HOME_DIR/.config/" 2>/dev/null || true
        
        log "Fixing permissions for .config..."
        exe chown -R "$TARGET_USER" "$HOME_DIR/.config"
    fi

    # --- Process .local ---
    if [ -d "$DOTFILES_SOURCE/.local" ]; then
        log "Merging .local..."
        if [ ! -d "$HOME_DIR/.local" ]; then mkdir -p "$HOME_DIR/.local"; fi
        
        exe cp -rf "$DOTFILES_SOURCE/.local/"* "$HOME_DIR/.local/" 2>/dev/null || true
        exe cp -rf "$DOTFILES_SOURCE/.local/." "$HOME_DIR/.local/" 2>/dev/null || true
        
        log "Fixing permissions for .local..."
        exe chown -R "$TARGET_USER" "$HOME_DIR/.local"
    fi
    
    success "KDE Dotfiles applied and permissions fixed."
else
    warn "Folder 'kde-dotfiles' not found in repo. Skipping config."
fi

# ------------------------------------------------------------------------------
# 4.5 Deploy Resource Files (README)
# ------------------------------------------------------------------------------
log "Deploying desktop resources..."

SOURCE_README="$PARENT_DIR/resources/KDE-README.txt"
DESKTOP_DIR="$HOME_DIR/Desktop"

if [ ! -d "$DESKTOP_DIR" ]; then
    exe runuser -u "$TARGET_USER" -- mkdir -p "$DESKTOP_DIR"
fi

if [ -f "$SOURCE_README" ]; then
    log "Copying KDE-README.txt..."
    exe cp "$SOURCE_README" "$DESKTOP_DIR/"
    exe chown "$TARGET_USER" "$DESKTOP_DIR/KDE-README.txt"
    success "Readme deployed."
else
    warn "resources/KDE-README.txt not found."
fi

# ------------------------------------------------------------------------------
# 5. Enable SDDM (FIXED THEME)
# ------------------------------------------------------------------------------
section "Step 5/5" "Enable Display Manager"

log "Configuring SDDM Theme to Breeze..."
exe mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/theme.conf <<EOF
[Theme]
Current=breeze
EOF
log "Theme set to 'breeze'."

log "Enabling SDDM..."
exe systemctl enable sddm
success "SDDM enabled. Will start on reboot."

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
section "Cleanup" "Restoring State"
rm -f "$SUDO_TEMP_FILE"
success "Done."

log "Module 06 completed."