#!/bin/bash

# ==============================================================================
# 04-niri-setup.sh - Niri Desktop (Final Optimized)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}
UNDO_SCRIPT="$SCRIPT_DIR/niri-undochange.sh"

# --- [CONFIGURATION] ---
# LazyVim 硬性依赖列表
LAZYVIM_DEPS=("neovim" "ripgrep" "fd" "ttf-jetbrains-mono-nerd" "git")

check_root

# --- [HELPER FUNCTIONS] ---

# 1. 简化的用户执行封装
as_user() {
    runuser -u "$TARGET_USER" -- "$@"
}

# 2. Critical Failure Handler (The "Big Red Box" - Safe Alignment)
critical_failure_handler() {
    local failed_reason="$1"
    trap - ERR

    echo ""
    echo -e "\033[0;31m################################################################\033[0m"
    echo -e "\033[0;31m#                                                              #\033[0m"
    echo -e "\033[0;31m#   CRITICAL INSTALLATION FAILURE DETECTED                     #\033[0m"
    echo -e "\033[0;31m#                                                              #\033[0m"
    echo -e "\033[0;31m#   Reason: $failed_reason\033[0m"
    echo -e "\033[0;31m#                                                              #\033[0m"
    echo -e "\033[0;31m#   OPTIONS:                                                   #\033[0m"
    echo -e "\033[0;31m#   1. Restore snapshot (Recommended safety rollback)          #\033[0m"
    echo -e "\033[0;31m#   2. Fix manually and re-run: sudo bash install.sh           #\033[0m"
    echo -e "\033[0;31m#                                                              #\033[0m"
    echo -e "\033[0;31m################################################################\033[0m"
    echo ""

    while true; do
        read -p "Execute System Recovery (Restore Snapshot)? [y/n]: " -r choice
        case "$choice" in 
            [yY]*) 
                if [ -f "$UNDO_SCRIPT" ]; then
                    warn "Executing recovery script..."
                    bash "$UNDO_SCRIPT"
                    exit 1
                else
                    error "Recovery script missing! You are on your own."
                    exit 1
                fi
                ;;
            [nN]*) 
                warn "User chose NOT to recover."
                warn "Please fix the issue manually before re-running."
                error "Installation aborted."
                exit 1 
                ;;
            *) echo "Invalid input. Please enter 'y' or 'n'." ;;
        esac
    done
}

# 3. 通用包安装验证函数
ensure_package_installed() {
    local pkg="$1"
    local context="$2" # e.g., "Repo" or "AUR"

    if pacman -Q "$pkg" &>/dev/null; then
        return 0
    fi

    warn "Package '$pkg' missing or failed. Retrying ($context)..."
    as_user yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$pkg" || true

    if ! pacman -Q "$pkg" &>/dev/null; then
        critical_failure_handler "Failed to install '$pkg' ($context)."
    fi
}

# Ensure whiptail
if ! command -v whiptail &> /dev/null; then
    log "Installing dependency: whiptail..."
    pacman -S --noconfirm libnewt >/dev/null 2>&1
fi

section "Phase 4" "Niri Desktop Environment"

# ==============================================================================
# STEP 0: Safety Checkpoint
# ==============================================================================

create_checkpoint() {
    local marker="Before Niri Setup"
    if snapper -c root list | grep -q "$marker"; then
        log "Checkpoint '$marker' already exists."
    else
        log "Creating safety checkpoint..."
        snapper -c root create -d "$marker"
        snapper -c home list &>/dev/null && snapper -c home create -d "$marker"
        success "Checkpoint created."
    fi
}
create_checkpoint

# Enable Trap
trap 'critical_failure_handler "Script Error at Line $LINENO"' ERR

# ==============================================================================
# STEP 1: Identify User & DM Check
# ==============================================================================
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# DM Check
KNOWN_DMS=("gdm" "sddm" "lightdm" "lxdm" "slim" "xorg-xdm" "ly" "greetd")
SKIP_AUTOLOGIN=false
DM_FOUND=""
for dm in "${KNOWN_DMS[@]}"; do
    if pacman -Q "$dm" &>/dev/null; then DM_FOUND="$dm"; break; fi
done

if [ -n "$DM_FOUND" ]; then
    info_kv "Conflict" "${H_RED}$DM_FOUND${NC}"
    SKIP_AUTOLOGIN=true
else
    read -t 20 -p "$(echo -e "   ${H_CYAN}Enable TTY auto-login? [Y/n] (Default Y): ${NC}")" choice || true
    [[ "${choice:-Y}" =~ ^[Yy]$ ]] && SKIP_AUTOLOGIN=false || SKIP_AUTOLOGIN=true
fi

# ==============================================================================
# STEP 2: Core Components (The ONLY -Syu)
# ==============================================================================
section "Step 1/9" "Core Components"
# Optimization: This is the ONLY time we refresh the database and update system
PKGS="niri xdg-desktop-portal-gnome fuzzel kitty firefox libnotify mako polkit-gnome"
exe pacman -Syu --noconfirm --needed $PKGS

log "Configuring Firefox Policies..."
POL_DIR="/etc/firefox/policies"
exe mkdir -p "$POL_DIR"
echo '{ "policies": { "Extensions": { "Install": ["https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"] } } }' > "$POL_DIR/policies.json"
exe chmod 755 "$POL_DIR" && exe chmod 644 "$POL_DIR/policies.json"

# ==============================================================================
# STEP 3: File Manager
# ==============================================================================
section "Step 2/9" "File Manager"
# Optimization: No -y or -u
exe pacman -S --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus

if [ ! -f /usr/bin/gnome-terminal ] || [ -L /usr/bin/gnome-terminal ]; then 
    exe ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
fi

# Nautilus Nvidia/Input Fix
DESKTOP_FILE="/usr/share/applications/org.gnome.Nautilus.desktop"
if [ -f "$DESKTOP_FILE" ]; then
    GPU_COUNT=$(lspci | grep -E -i "vga|3d" | wc -l)
    HAS_NVIDIA=$(lspci | grep -E -i "nvidia" | wc -l)
    ENV_VARS="env GTK_IM_MODULE=fcitx"
    [ "$GPU_COUNT" -gt 1 ] && [ "$HAS_NVIDIA" -gt 0 ] && ENV_VARS="env GSK_RENDERER=gl GTK_IM_MODULE=fcitx"
    
    if ! grep -q "^Exec=$ENV_VARS" "$DESKTOP_FILE"; then
        exe sed -i "s|^Exec=|Exec=$ENV_VARS |" "$DESKTOP_FILE"
    fi
fi

# ==============================================================================
# STEP 4: Network Optimization
# ==============================================================================
section "Step 3/9" "Network Optimization"
exe pacman -S --noconfirm --needed flatpak gnome-software
exe flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

CURRENT_TZ=$(readlink -f /etc/localtime)
IS_CN_ENV=false
if [[ "$CURRENT_TZ" == *"Shanghai"* ]] || [ "$CN_MIRROR" == "1" ] || [ "$DEBUG" == "1" ]; then
    IS_CN_ENV=true
    info_kv "Region" "China Optimization Active"
fi

if [ "$IS_CN_ENV" = true ]; then
    select_flathub_mirror
else
    log "Using Global Sources."
fi

SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

# ==============================================================================
# STEP 5: Dependencies (Updated)
# ==============================================================================
section "Step 4/9" "Dependencies"
LIST_FILE="$PARENT_DIR/niri-applist.txt"

# Ensure tools
command -v fzf &> /dev/null || pacman -S --noconfirm fzf >/dev/null 2>&1

if [ -f "$LIST_FILE" ]; then
    mapfile -t DEFAULT_LIST < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed 's/#.*//; s/AUR://g' | xargs -n1)

    if [ ${#DEFAULT_LIST[@]} -eq 0 ]; then
        warn "App list is empty. Skipping."
        PACKAGE_ARRAY=()
    else
        echo -e "\n   ${H_YELLOW}>>> Default installation in 60s. Press ANY KEY to customize...${NC}"
        if read -t 60 -n 1 -s -r; then
            # FZF Selection Logic
            clear
            log "Loading package list..."
            SELECTED_LINES=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed -E 's/[[:space:]]+#/\t#/' | \
                fzf --multi --layout=reverse --border --prompt="Search > " --delimiter=$'\t' --with-nth=1 --preview "echo {} | cut -f2 -d$'\t'")
            
            clear
            PACKAGE_ARRAY=()
            if [ -n "$SELECTED_LINES" ]; then
                while IFS= read -r line; do
                    clean_pkg=$(echo "$line" | cut -f1 -d$'\t' | xargs)
                    clean_pkg="${clean_pkg#AUR:}"
                    [ -n "$clean_pkg" ] && PACKAGE_ARRAY+=("$clean_pkg")
                done <<< "$SELECTED_LINES"
            fi
        else
            log "Auto-confirming ALL packages."
            PACKAGE_ARRAY=("${DEFAULT_LIST[@]}")
        fi
    fi

    # --- Pre-Installation Filter (LazyVim Interceptor) ---
    INSTALL_LAZYVIM=false
    FINAL_ARRAY=()
    if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
        for pkg in "${PACKAGE_ARRAY[@]}"; do
            if [ "${pkg,,}" == "lazyvim" ]; then # ${var,,} converts to lowercase
                INSTALL_LAZYVIM=true
                FINAL_ARRAY+=("${LAZYVIM_DEPS[@]}")
                info_kv "Config" "LazyVim detected" "Setup deferred to post-dotfiles"
            else
                FINAL_ARRAY+=("$pkg")
            fi
        done
        PACKAGE_ARRAY=("${FINAL_ARRAY[@]}")
    fi

    # --- Installation Loop ---
    if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
        BATCH_LIST=()
        AUR_LIST=()
        info_kv "Target" "${#PACKAGE_ARRAY[@]} packages scheduled."

        for pkg in "${PACKAGE_ARRAY[@]}"; do
            [ "$pkg" == "imagemagic" ] && pkg="imagemagick"
            [[ "$pkg" == "AUR:"* ]] && AUR_LIST+=("${pkg#AUR:}") || BATCH_LIST+=("$pkg")
        done

        # 1. Batch Install Repo Packages
        if [ ${#BATCH_LIST[@]} -gt 0 ]; then
            log "Phase 1: Batch Installing Repo Packages..."
            # Using || true to prevent exit on minor errors, handled by verification
            as_user yay -S --noconfirm --needed --answerdiff=None --answerclean=None "${BATCH_LIST[@]}" || true
            
            # Verify Each
            for pkg in "${BATCH_LIST[@]}"; do
                ensure_package_installed "$pkg" "Repo"
            done
        fi

        # 2. Sequential AUR Install
        if [ ${#AUR_LIST[@]} -gt 0 ]; then
            log "Phase 2: Installing AUR Packages..."
            for pkg in "${AUR_LIST[@]}"; do
                ensure_package_installed "$pkg" "AUR"
            done
        fi
        
        # Waybar fallback
        if ! command -v waybar &> /dev/null; then
            warn "Waybar missing. Installing stock..."
            exe pacman -S --noconfirm --needed waybar
        fi
        
        # Note: LazyVim configuration is deliberately skipped here to avoid 
        # backup conflicts with the Dotfiles step. It runs in Step 6.
    else
        warn "No packages selected."
    fi
else
    warn "niri-applist.txt not found."
fi

# ==============================================================================
# STEP 6: Dotfiles & LazyVim
# ==============================================================================
section "Step 5/9" "Deploying Dotfiles"

REPO_GITHUB="https://github.com/SHORiN-KiWATA/ShorinArchExperience-ArchlinuxGuide.git"
REPO_GITEE="https://gitee.com/shorinkiwata/ShorinArchExperience-ArchlinuxGuide.git"
TEMP_DIR="/tmp/shorin-repo"
rm -rf "$TEMP_DIR"

log "Cloning configuration..."
if ! as_user git clone "$REPO_GITHUB" "$TEMP_DIR"; then
    warn "GitHub failed. Trying Gitee..."
    rm -rf "$TEMP_DIR"
    if ! as_user git clone "$REPO_GITEE" "$TEMP_DIR"; then
        critical_failure_handler "Failed to clone dotfiles from any source."
    fi
fi

if [ -d "$TEMP_DIR/dotfiles" ]; then
    # Filter Exclusions
    if [ "$TARGET_USER" != "shorin" ]; then
        EXCLUDE_FILE="$PARENT_DIR/exclude-dotfiles.txt"
        if [ -f "$EXCLUDE_FILE" ]; then
            log "Processing exclusions..."
            while IFS= read -r item; do
                item=$(echo "$item" | tr -d '\r' | xargs)
                [ -n "$item" ] && [[ ! "$item" =~ ^# ]] && rm -rf "$TEMP_DIR/dotfiles/.config/$item"
            done < "$EXCLUDE_FILE"
        fi
    fi

    # Backup & Apply
    log "Backing up & Applying..."
    as_user tar -czf "$HOME_DIR/config_backup_$(date +%s).tar.gz" -C "$HOME_DIR" .config
    as_user cp -rf "$TEMP_DIR/dotfiles/." "$HOME_DIR/"

    # Post-Process
    if [ "$TARGET_USER" != "shorin" ]; then
        as_user truncate -s 0 "$HOME_DIR/.config/niri/output.kdl" 2>/dev/null
        rm -f "$HOME_DIR/.config/gtk-3.0/bookmarks"
    fi

    # Fix Symlinks & Permissions
    GTK4="$HOME_DIR/.config/gtk-4.0"
    THEME="$HOME_DIR/.themes/adw-gtk3-dark/gtk-4.0"
    as_user rm -f "$GTK4/gtk.css" "$GTK4/gtk-dark.css"
    as_user ln -sf "$THEME/gtk-dark.css" "$GTK4/gtk-dark.css"
    as_user ln -sf "$THEME/gtk.css" "$GTK4/gtk.css"

    if command -v flatpak &>/dev/null; then
        as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
        as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
        as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    fi
    success "Dotfiles Applied."
else
    warn "Dotfiles missing in temp directory."
fi

# --- Post-Dotfiles Configuration: LazyVim ---
if [ "$INSTALL_LAZYVIM" = true ]; then
    section "Config" "Applying LazyVim Overrides"
    NVIM_CFG="$HOME_DIR/.config/nvim"
    
    # Check if dotfiles or existing install put something here
    if [ -d "$NVIM_CFG" ]; then
        BACKUP_PATH="$HOME_DIR/.config/nvim.old.dotfiles.$(date +%s)"
        warn "Collision detected. Moving existing nvim config to $BACKUP_PATH"
        mv "$NVIM_CFG" "$BACKUP_PATH"
    fi
    
    log "Cloning LazyVim starter..."
    if as_user git clone https://github.com/LazyVim/starter "$NVIM_CFG"; then
        rm -rf "$NVIM_CFG/.git"
        success "LazyVim installed (Override)."
    else
        error "Failed to clone LazyVim."
    fi
fi

# ==============================================================================
# STEP 7: Wallpapers
# ==============================================================================
section "Step 6/9" "Wallpapers"
if [ -d "$TEMP_DIR/wallpapers" ]; then
    as_user mkdir -p "$HOME_DIR/Pictures/Wallpapers"
    as_user cp -rf "$TEMP_DIR/wallpapers/." "$HOME_DIR/Pictures/Wallpapers/"
    success "Installed."
fi
rm -rf "$TEMP_DIR"

# ==============================================================================
# STEP 8: Hardware Tools
# ==============================================================================
section "Step 7/9" "Hardware"
if pacman -Q ddcutil &>/dev/null; then
    gpasswd -a "$TARGET_USER" i2c
    lsmod | grep -q i2c_dev || echo "i2c-dev" > /etc/modules-load.d/i2c-dev.conf
fi
if pacman -Q swayosd &>/dev/null; then
    systemctl enable --now swayosd-libinput-backend.service >/dev/null 2>&1
fi
success "Tools configured."

# ==============================================================================
# STEP 9: Cleanup & Auto-Login
# ==============================================================================
section "Final" "Cleanup & Boot"
rm -f "$SUDO_TEMP_FILE"

SVC_DIR="$HOME_DIR/.config/systemd/user"
SVC_FILE="$SVC_DIR/niri-autostart.service"
LINK="$SVC_DIR/default.target.wants/niri-autostart.service"

if [ "$SKIP_AUTOLOGIN" = true ]; then
    log "Auto-login skipped."
    as_user rm -f "$LINK" "$SVC_FILE"
else
    log "Configuring TTY Auto-login..."
    mkdir -p "/etc/systemd/system/getty@tty1.service.d"
    echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}" > "/etc/systemd/system/getty@tty1.service.d/autologin.conf"
    
    as_user mkdir -p "$(dirname "$LINK")"
    cat <<EOT > "$SVC_FILE"
[Unit]
Description=Niri Session Autostart
After=graphical-session-pre.target
[Service]
ExecStart=/usr/bin/niri-session
Restart=on-failure
[Install]
WantedBy=default.target
EOT
    as_user ln -sf "../niri-autostart.service" "$LINK"
    # Ensure ownership is correct if root touched it
    chown -R "$TARGET_USER:$TARGET_USER" "$SVC_DIR"
    success "Enabled."
fi

trap - ERR
log "Module 04 completed."