#!/bin/bash

# ==============================================================================
# 04-niri-setup.sh - Niri Desktop (Visual Enhanced & Logic Refactored)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}

check_root

section "Phase 4" "Niri Desktop Environment"

# ------------------------------------------------------------------------------
# 0. Identify Target User
# ------------------------------------------------------------------------------
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
if [ -n "$DETECTED_USER" ]; then TARGET_USER="$DETECTED_USER"; else read -p "Target user: " TARGET_USER; fi
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# ------------------------------------------------------------------------------
# [SAFETY CHECK] DM Detection
# ------------------------------------------------------------------------------
log "Checking Display Managers..."
KNOWN_DMS=("gdm" "sddm" "lightdm" "lxdm" "slim" "xorg-xdm" "ly" "greetd")
SKIP_AUTOLOGIN=false
DM_FOUND=""
for dm in "${KNOWN_DMS[@]}"; do
    if pacman -Q "$dm" &>/dev/null; then DM_FOUND="$dm"; break; fi
done

if [ -n "$DM_FOUND" ]; then
    info_kv "Conflict" "${H_RED}$DM_FOUND${NC}" "Package detected"
    warn "TTY auto-login will be DISABLED."
    SKIP_AUTOLOGIN=true
else
    info_kv "DM Check" "None"
    read -t 20 -p "$(echo -e "   ${H_CYAN}Enable TTY auto-login? [Y/n] (Default Y in 20s): ${NC}")" choice
    if [ $? -ne 0 ]; then echo ""; fi
    choice=${choice:-Y}
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then SKIP_AUTOLOGIN=true; else SKIP_AUTOLOGIN=false; fi
fi

# ------------------------------------------------------------------------------
# 1. Install Core
# ------------------------------------------------------------------------------
section "Step 1/9" "Core Components"
PKGS="niri xdg-desktop-portal-gnome fuzzel kitty libnotify mako polkit-gnome"
exe pacman -Syu --noconfirm --needed $PKGS

log "Configuring Firefox Policies..."
FIREFOX_POLICY_DIR="/etc/firefox/policies"
exe mkdir -p "$FIREFOX_POLICY_DIR"
cat <<EOT > "$FIREFOX_POLICY_DIR/policies.json"
{
  "policies": { "Extensions": { "Install": ["https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"] } }
}
EOT
exe chmod 755 "$FIREFOX_POLICY_DIR"
exe chmod 644 "$FIREFOX_POLICY_DIR/policies.json"
success "Firefox policy applied."

# ------------------------------------------------------------------------------
# 2. File Manager
# ------------------------------------------------------------------------------
section "Step 2/9" "File Manager"
exe pacman -Syu --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus
if [ ! -f /usr/bin/gnome-terminal ] || [ -L /usr/bin/gnome-terminal ]; then exe ln -sf /usr/bin/kitty /usr/bin/gnome-terminal; fi
DESKTOP_FILE="/usr/share/applications/org.gnome.Nautilus.desktop"
if [ -f "$DESKTOP_FILE" ]; then
    GPU_COUNT=$(lspci | grep -E -i "vga|3d" | wc -l)
    HAS_NVIDIA=$(lspci | grep -E -i "nvidia" | wc -l)
    ENV_VARS="env GTK_IM_MODULE=fcitx"
    if [ "$GPU_COUNT" -gt 1 ] && [ "$HAS_NVIDIA" -gt 0 ]; then ENV_VARS="env GSK_RENDERER=gl GTK_IM_MODULE=fcitx"; fi
    
    # Check if the line is already modified to prevent duplicate entries
    if ! grep -q "^Exec=$ENV_VARS" "$DESKTOP_FILE"; then
        exe sed -i "s|^Exec=|Exec=$ENV_VARS |" "$DESKTOP_FILE"
    fi
fi

# ------------------------------------------------------------------------------
# 3. Network Optimization
# ------------------------------------------------------------------------------
section "Step 3/9" "Network Optimization"
exe pacman -Syu --noconfirm --needed flatpak gnome-software
exe flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

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

if [ "$IS_CN_ENV" = true ]; then
    log "Enabling China Optimizations..."
    
    select_flathub_mirror
    
    success "Optimizations Enabled."
else
    log "Using Global Sources."
fi

log "Configuring temporary sudo access..."
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

# ------------------------------------------------------------------------------
# 4. Dependencies (LOGIC FIXED: Verification via pacman -Q)
# ------------------------------------------------------------------------------
section "Step 4/9" "Dependencies"
LIST_FILE="$PARENT_DIR/niri-applist.txt"
UNDO_SCRIPT="$PARENT_DIR/undochange.sh"

# --- Critical Failure Handler ---
critical_failure_handler() {
    local failed_pkg="$1"
    
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
                # 修改了这里：使用 \033[1;33m (亮黄色) 和 -e 参数
                echo -e "\033[1;33mInvalid input. Please enter 'y' to recover or 'n' to abort.\033[0m"
                ;;
        esac
    done
}

# --- Verification Function ---
verify_installation() {
    local pkg="$1"
    # 使用 pacman -Q 检查包是否存在，重定向输出避免干扰
    if pacman -Q "$pkg" &>/dev/null; then
        return 0 # 已安装
    else
        return 1 # 未安装
    fi
}

if [ -f "$LIST_FILE" ]; then
    mapfile -t PACKAGE_ARRAY < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | tr -d '\r')
    
    if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
        BATCH_LIST=()
        AUR_LIST=()

        # 1. Parse List & Separate
        for pkg in "${PACKAGE_ARRAY[@]}"; do
            [ "$pkg" == "imagemagic" ] && pkg="imagemagick"
            if [[ "$pkg" == "AUR:"* ]]; then
                clean_pkg="${pkg#AUR:}"
                AUR_LIST+=("$clean_pkg")
            else
                BATCH_LIST+=("$pkg")
            fi
        done

        # 2. Phase 1: Batch Install (Repo Packages)
        if [ ${#BATCH_LIST[@]} -gt 0 ]; then
            log "Phase 1: Batch Installing Repository Packages..."
            
            # 尝试安装
            exe runuser -u "$TARGET_USER" -- yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "${BATCH_LIST[@]}"
            
            # --- [关键修改] 批量安装后，逐一核查 ---
            log "Verifying batch installation..."
            for pkg in "${BATCH_LIST[@]}"; do
                if ! verify_installation "$pkg"; then
                    warn "Verification failed for '$pkg'. Retrying individually..."
                    # 失败重试：单独安装这一个
                    exe runuser -u "$TARGET_USER" -- yay -Syu --noconfirm --needed "$pkg"
                    
                    # 二次核查
                    if ! verify_installation "$pkg"; then
                        critical_failure_handler "$pkg (Repo)"
                    else
                        success "Verified: $pkg"
                    fi
                fi
            done
            success "Batch phase verification complete."
        fi

        # 3. Phase 2: Sequential Install (AUR Packages)
        if [ ${#AUR_LIST[@]} -gt 0 ]; then
            log "Phase 2: Installing AUR Packages (Sequential)..."
            log "Hint: Use Ctrl+C to skip a specific package download step."

            for aur_pkg in "${AUR_LIST[@]}"; do
                log "Installing '$aur_pkg'..."
                
                # Try 1
                runuser -u "$TARGET_USER" -- yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "$aur_pkg"
                EXIT_CODE=$?

                # Ctrl+C 跳过处理
                if [ $EXIT_CODE -eq 130 ]; then
                    warn "Skipped '$aur_pkg' by user request (Ctrl+C)."
                    continue
                fi

                # --- [关键修改] 核查安装结果 ---
                if ! verify_installation "$aur_pkg"; then
                    warn "Verification failed for '$aur_pkg'. Retrying once..."
                    
                    # Retry 1
                    runuser -u "$TARGET_USER" -- yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "$aur_pkg"
                    RETRY_CODE=$?

                    if [ $RETRY_CODE -eq 130 ]; then
                         warn "Skipped '$aur_pkg' on retry by user request (Ctrl+C)."
                         continue
                    fi

                    # 二次核查
                    if ! verify_installation "$aur_pkg"; then
                        critical_failure_handler "$aur_pkg (AUR)"
                    else
                         success "Verified: $aur_pkg"
                    fi
                else
                    success "Verified: $aur_pkg"
                fi
            done
        fi
    
        # Recovery Check
        if ! command -v waybar &> /dev/null; then
            warn "Waybar missing. Installing stock..."
            exe pacman -Syu --noconfirm --needed waybar
        fi

    fi
else
    warn "niri-applist.txt not found."
fi

# ------------------------------------------------------------------------------
# 5. Dotfiles
# ------------------------------------------------------------------------------
section "Step 5/9" "Deploying Dotfiles"

# Define URLs
REPO_GITHUB="https://github.com/SHORiN-KiWATA/ShorinArchExperience-ArchlinuxGuide.git"
REPO_GITEE="https://gitee.com/shorinkiwata/ShorinArchExperience-ArchlinuxGuide.git"
TEMP_DIR="/tmp/shorin-repo"

# Ensure clean start
rm -rf "$TEMP_DIR"

log "Cloning configuration repository..."

# Attempt 1: GitHub
if exe runuser -u "$TARGET_USER" -- git clone "$REPO_GITHUB" "$TEMP_DIR"; then
    success "Cloned successfully (Source: GitHub)."
else
    warn "GitHub clone failed. Attempting fallback to Gitee..."
    
    # Clean partial files from failed attempt
    rm -rf "$TEMP_DIR"
    
    # Attempt 2: Gitee
    if exe runuser -u "$TARGET_USER" -- git clone "$REPO_GITEE" "$TEMP_DIR"; then
        success "Cloned successfully (Source: Gitee)."
    else
        error "Clone failed from both GitHub and Gitee."
    fi
fi

if [ -d "$TEMP_DIR/dotfiles" ]; then
    # --- Check UID 1000 and remove bookmarks if not shorin ---
    UID1000_USER=$(id -nu 1000 2>/dev/null)
    
    if [ "$UID1000_USER" != "shorin" ]; then
        log "UID 1000 user ($UID1000_USER) is not shorin. Removing gtk bookmarks..."
        rm -f "$TEMP_DIR/dotfiles/.config/gtk-3.0/bookmarks"
    fi
    # ---------------------------------------------------------

    BACKUP_NAME="config_backup_$(date +%s).tar.gz"
    log "Backing up..."
    exe runuser -u "$TARGET_USER" -- tar -czf "$HOME_DIR/$BACKUP_NAME" -C "$HOME_DIR" .config
    
    log "Applying..."
    exe runuser -u "$TARGET_USER" -- cp -rf "$TEMP_DIR/dotfiles/." "$HOME_DIR/"

    # --- Re-link GTK 4.0 Assets for dynamic user path ---
    log "Fixing GTK 4.0 symlinks..."
    GTK4_CONF="$HOME_DIR/.config/gtk-4.0"
    THEME_SRC="$HOME_DIR/.themes/adw-gtk3-dark/gtk-4.0"

    exe runuser -u "$TARGET_USER" -- rm -rfv "$GTK4_CONF/assets" "$GTK4_CONF/gtk.css" "$GTK4_CONF/gtk-dark.css"
    exe runuser -u "$TARGET_USER" -- ln -sf "$THEME_SRC/gtk-dark.css" "$GTK4_CONF/gtk-dark.css"
    exe runuser -u "$TARGET_USER" -- ln -sf "$THEME_SRC/gtk.css" "$GTK4_CONF/gtk.css"
    exe runuser -u "$TARGET_USER" -- ln -sf "$THEME_SRC/assets" "$GTK4_CONF/assets"

    # --- Apply Flatpak GTK Theming Overrides ---
    if command -v flatpak &>/dev/null; then
        log "Applying Flatpak GTK theme overrides..."
        exe runuser -u "$TARGET_USER" -- flatpak override --user --filesystem="$HOME_DIR/.themes"
        exe runuser -u "$TARGET_USER" -- flatpak override --user --filesystem=xdg-config/gtk-4.0
        exe runuser -u "$TARGET_USER" -- flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    fi

    success "Applied."
    
    if [ "$TARGET_USER" != "shorin" ]; then
        log "Cleaning output.kdl..."
        exe runuser -u "$TARGET_USER" -- truncate -s 0 "$HOME_DIR/.config/niri/output.kdl"
        # Clean excluded
        EXCLUDE_FILE="$PARENT_DIR/exclude-dotfiles.txt"
        if [ -f "$EXCLUDE_FILE" ]; then
            mapfile -t EXCLUDES < <(grep -vE "^\s*#|^\s*$" "$EXCLUDE_FILE" | tr -d '\r')
            for item in "${EXCLUDES[@]}"; do
                item=$(echo "$item" | xargs)
                [ -z "$item" ] && continue
                RM_PATH="$HOME_DIR/.config/$item"
                if [ -d "$RM_PATH" ]; then exe rm -rf "$RM_PATH"; fi
            done
        fi
    fi
else
    warn "Dotfiles missing."
fi

# ------------------------------------------------------------------------------
# 6. Wallpapers
# ------------------------------------------------------------------------------
section "Step 6/9" "Wallpapers"
WALL_DEST="$HOME_DIR/Pictures/Wallpapers"
if [ -d "$TEMP_DIR/wallpapers" ]; then
    exe runuser -u "$TARGET_USER" -- mkdir -p "$WALL_DEST"
    exe runuser -u "$TARGET_USER" -- cp -rf "$TEMP_DIR/wallpapers/." "$WALL_DEST/"
    success "Installed."
fi
rm -rf "$TEMP_DIR"

# ------------------------------------------------------------------------------
# 7. Hardware Tools
# ------------------------------------------------------------------------------
section "Step 7/9" "Hardware"
exe runuser -u "$TARGET_USER" -- yay -Syu --noconfirm --needed ddcutil-service
gpasswd -a "$TARGET_USER" i2c
exe pacman -Syu --noconfirm --needed swayosd
systemctl enable --now swayosd-libinput-backend.service > /dev/null 2>&1
success "Tools configured."

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
section "Step 9/9" "Cleanup"
rm -f "$SUDO_TEMP_FILE"
success "Done."

# ------------------------------------------------------------------------------
# 10. Auto-Login
# ------------------------------------------------------------------------------
section "Final" "Boot Config"
USER_SYSTEMD_DIR="$HOME_DIR/.config/systemd/user"
WANTS_DIR="$USER_SYSTEMD_DIR/default.target.wants"
LINK_PATH="$WANTS_DIR/niri-autostart.service"
SERVICE_FILE="$USER_SYSTEMD_DIR/niri-autostart.service"

if [ "$SKIP_AUTOLOGIN" = true ]; then
    log "Auto-login skipped."
    if [ -f "$LINK_PATH" ] || [ -f "$SERVICE_FILE" ]; then
        warn "Cleaning old auto-login..."
        exe rm -f "$LINK_PATH"
        exe rm -f "$SERVICE_FILE"
    fi
else
    log "Configuring TTY Auto-login..."
    GETTY_DIR="/etc/systemd/system/getty@tty1.service.d"
    mkdir -p "$GETTY_DIR"
    cat <<EOT > "$GETTY_DIR/autologin.conf"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}
EOT
    exe mkdir -p "$USER_SYSTEMD_DIR"
    cat <<EOT > "$SERVICE_FILE"
[Unit]
Description=Niri Session Autostart
After=graphical-session-pre.target

[Service]
ExecStart=/usr/bin/niri-session
Restart=on-failure

[Install]
WantedBy=default.target
EOT
    exe mkdir -p "$WANTS_DIR"
    exe ln -sf "../niri-autostart.service" "$LINK_PATH"
    exe chown -R "$TARGET_USER" "$HOME_DIR/.config/systemd"
    success "Enabled."
fi

log "Module 04 completed."