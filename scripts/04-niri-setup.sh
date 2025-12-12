#!/bin/bash

# ==============================================================================
# 04-niri-setup.sh - Niri Desktop (Visual Enhanced & Interactive Rollback)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}

# 定义回滚脚本位置
UNDO_SCRIPT="$SCRIPT_DIR/niri-undochange.sh"

check_root

# Ensure whiptail is installed for TUI
if ! command -v whiptail &> /dev/null; then
    log "Installing dependency: whiptail (libnewt)..."
    pacman -S --noconfirm libnewt >/dev/null 2>&1
fi

section "Phase 4" "Niri Desktop Environment"

# ==============================================================================
# [NEW] STEP 0: Safety Checkpoint & Critical Error Handler
# ==============================================================================

# 1. Create Checkpoint
create_checkpoint() {
    local marker="Before Niri Setup"
    
    if snapper -c root list | grep -q "$marker"; then
        log "Checkpoint '$marker' already exists. Ready to proceed."
    else
        log "Creating safety checkpoint: '$marker'..."
        snapper -c root create -d "$marker"
        if snapper -c home list &>/dev/null; then
            snapper -c home create -d "$marker"
        fi
        success "Checkpoint created."
    fi
}

create_checkpoint

# 2. Critical Failure Handler (The "Big Red Box" Interactive Logic)
critical_failure_handler() {
    local failed_reason="$1"
    
    # Disable trap to prevent loops during input
    trap - ERR

    echo ""
    echo -e "\033[0;31m################################################################\033[0m"
    echo -e "\033[0;31m#                                                              #\033[0m"
    echo -e "\033[0;31m#   CRITICAL INSTALLATION FAILURE DETECTED                     #\033[0m"
    echo -e "\033[0;31m#   Reason: $failed_reason                                     #\033[0m"
    echo -e "\033[0;31m#   Status: System might be in an inconsistent state.          #\033[0m"
    echo -e "\033[0;31m#                                                              #\033[0m"
    echo -e "\033[0;31m#   Would you like to restore snapshot (undo changes)?         #\033[0m"
    echo -e "\033[0;31m################################################################\033[0m"
    echo ""

    while true; do
        # No default option (-p prompt only)
        read -p "Execute System Recovery? [y/n]: " -r choice
        case "$choice" in 
            [yY][eE][sS]|[yY]) 
                if [ -f "$UNDO_SCRIPT" ]; then
                    warn "Executing recovery script: $UNDO_SCRIPT"
                    bash "$UNDO_SCRIPT"
                    exit 1 # The undo script handles reboot, but just in case
                else
                    error "Recovery script not found at: $UNDO_SCRIPT"
                    error "You are on your own. Good luck."
                    exit 1
                fi
                ;;
            [nN][oO]|[nN])
                warn "User chose NOT to recover. System might be in a broken state."
                error "Installation aborted."
                exit 1
                ;;
            *)
                echo -e "\033[1;33mInvalid input. Please enter 'y' to recover or 'n' to abort.\033[0m"
                ;;
        esac
    done
}

# 3. Enable Trap for Unexpected Errors
# If the script crashes (syntax error, command failed outside of our manual checks),
# it calls the handler with line number.
trap 'critical_failure_handler "Script Error at Line $LINENO"' ERR


# ==============================================================================
# STEP 1: Identify User & DM Check
# ==============================================================================
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
if [ -n "$DETECTED_USER" ]; then TARGET_USER="$DETECTED_USER"; else read -p "Target user: " TARGET_USER; fi
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

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
    # Using || true to ensure read timeout doesn't trigger TRAP ERR
    read -t 20 -p "$(echo -e "   ${H_CYAN}Enable TTY auto-login? [Y/n] (Default Y in 20s): ${NC}")" choice || true
    if [ $? -ne 0 ]; then echo ""; fi
    choice=${choice:-Y}
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then SKIP_AUTOLOGIN=true; else SKIP_AUTOLOGIN=false; fi
fi

# ==============================================================================
# STEP 2: Core Components
# ==============================================================================
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

# ==============================================================================
# STEP 3: File Manager
# ==============================================================================
section "Step 2/9" "File Manager"
exe pacman -Syu --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus
if [ ! -f /usr/bin/gnome-terminal ] || [ -L /usr/bin/gnome-terminal ]; then exe ln -sf /usr/bin/kitty /usr/bin/gnome-terminal; fi
DESKTOP_FILE="/usr/share/applications/org.gnome.Nautilus.desktop"
if [ -f "$DESKTOP_FILE" ]; then
    GPU_COUNT=$(lspci | grep -E -i "vga|3d" | wc -l)
    HAS_NVIDIA=$(lspci | grep -E -i "nvidia" | wc -l)
    ENV_VARS="env GTK_IM_MODULE=fcitx"
    if [ "$GPU_COUNT" -gt 1 ] && [ "$HAS_NVIDIA" -gt 0 ]; then ENV_VARS="env GSK_RENDERER=gl GTK_IM_MODULE=fcitx"; fi
    
    if ! grep -q "^Exec=$ENV_VARS" "$DESKTOP_FILE"; then
        exe sed -i "s|^Exec=|Exec=$ENV_VARS |" "$DESKTOP_FILE"
    fi
fi

# ==============================================================================
# STEP 4: Network Optimization
# ==============================================================================
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

# ==============================================================================
# STEP 5: Dependencies (Archinstall-style TUI with FZF)
# ==============================================================================
section "Step 4/9" "Dependencies"
LIST_FILE="$PARENT_DIR/niri-applist.txt"

# 0. 确保安装了 FZF (实现 TUI 的核心工具)
if ! command -v fzf &> /dev/null; then
    log "Installing dependency: fzf (for advanced menu)..."
    pacman -S --noconfirm fzf >/dev/null 2>&1
fi

# Verification Function
verify_installation() {
    local pkg="$1"
    if pacman -Q "$pkg" &>/dev/null; then return 0; else return 1; fi
}

if [ -f "$LIST_FILE" ]; then
    log "Launching Archinstall-style Package Selection..."
    
# -------------------------------------------------------------
    # FZF TUI Logic (Clean Layout & Correct Color Syntax)
    # -------------------------------------------------------------
    
    # 1. 进场清屏
    clear
    echo -e "\n  Loading package list..."

    # 2. 启动 FZF
    # 修正说明: 
    #   1. 颜色语法改为 header:yellow:bold (冒号分隔)
    #   2. marker:green:bold
    #   3. pointer:cyan:bold
    
    SELECTED_LINES=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | \
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
            --header=" [ TAB ] TOGGLE | [ ENTER ] CONFIRM | [ CTRL-D ] DESELECT ALL | [CTRL-A] SELEDCT ALL" \
            --preview "echo {} | cut -f2 -d$'\t' | sed 's/^# //'" \
            --preview-window=right:50%:wrap:border-left \
            --color=dark \
            --color=fg+:white,bg+:black \
            --color=hl:blue,hl+:blue:bold \
            --color=header:yellow:bold \
            --color=info:magenta \
            --color=prompt:cyan,pointer:cyan:bold,marker:green:bold \
            --color=spinner:yellow)
    
    # 3. 出场清屏
    clear

    # Check if user cancelled
    if [ -z "$SELECTED_LINES" ]; then
        warn "User cancelled package selection or selected nothing."
        PACKAGE_ARRAY=()
    else
        # 4. 解析结果
        PACKAGE_ARRAY=()
        while IFS= read -r line; do
            # 提取 Tab 键前面的内容
            pkg_clean=$(echo "$line" | cut -f1 -d$'\t' | xargs)
            if [ -n "$pkg_clean" ]; then
                PACKAGE_ARRAY+=("$pkg_clean")
            fi
        done <<< "$SELECTED_LINES"
    fi
    
    # -------------------------------------------------------------
    
    # -------------------------------------------------------------
    
    # Check if user cancelled (Empty output)
    if [ -z "$SELECTED_LINES" ]; then
        warn "User cancelled package selection or selected nothing."
        PACKAGE_ARRAY=()
    else
        # 3. 解析结果
        # fzf 返回的是整行 (例如 "firefox # 浏览器")
        # 我们需要提取出包名 (空格前的部分)
        PACKAGE_ARRAY=()
        while IFS= read -r line; do
            # 提取 # 前面的部分，并去除两端空格
            pkg_part="${line%%#*}"
            pkg_clean=$(echo "$pkg_part" | xargs)
            if [ -n "$pkg_clean" ]; then
                PACKAGE_ARRAY+=("$pkg_clean")
            fi
        done <<< "$SELECTED_LINES"
    fi

    # -------------------------------------------------------------
    # End TUI Logic
    # -------------------------------------------------------------
    
    if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
        BATCH_LIST=()
        AUR_LIST=()

        info_kv "Selection" "${#PACKAGE_ARRAY[@]} packages scheduled."

        # Classification Logic (Unchanged)
        for pkg in "${PACKAGE_ARRAY[@]}"; do
            [ "$pkg" == "imagemagic" ] && pkg="imagemagick"
            
            # Check for AUR prefix explicitly or implicit logic
            if [[ "$pkg" == "AUR:"* ]]; then
                clean_pkg="${pkg#AUR:}"
                AUR_LIST+=("$clean_pkg")
            elif [[ "$pkg" == *"-git" ]] || [[ "$pkg" == *"-bin" ]]; then
                # Simple heuristic: usually -git/-bin are AUR, but not always. 
                # Better to stick to your LIST definition or let yay handle it.
                # Here we assume your list uses AUR: prefix OR we treat everything as 'yay' target
                # Yay handles repo vs aur automatically, so separating is mostly for batch speed.
                
                # Let's trust yay's auto-detection for simplicity unless specifically prefixed
                BATCH_LIST+=("$pkg")
            else
                BATCH_LIST+=("$pkg")
            fi
        done

        # --- Phase 1: Batch Install (Using Yay for everything is often safer for mixing) ---
        # However, to keep your robust error handling, we verify repo packages first.
        
        if [ ${#BATCH_LIST[@]} -gt 0 ]; then
            log "Phase 1: Installing Selected Packages..."
            
            # We construct one giant command. Yay handles mixed Repo/AUR gracefully usually.
            # But adhering to your request for robustness:
            
            exe runuser -u "$TARGET_USER" -- yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "${BATCH_LIST[@]}" "${AUR_LIST[@]}" || true
            
            # Verify ALL
            log "Verifying installation..."
            ALL_PKGS=("${BATCH_LIST[@]}" "${AUR_LIST[@]}")
            
            for pkg in "${ALL_PKGS[@]}"; do
                if ! verify_installation "$pkg"; then
                    warn "Verification failed for '$pkg'. Retrying individually..."
                    exe runuser -u "$TARGET_USER" -- yay -Syu --noconfirm --needed "$pkg" || true
                    
                    if ! verify_installation "$pkg"; then
                         # Trigger the Big Red Box
                        critical_failure_handler "Failed to install '$pkg' after retry."
                    else
                        success "Verified: $pkg"
                    fi
                fi
            done
            success "Installation phase complete."
        fi

        # Recovery Check
        if ! command -v waybar &> /dev/null; then
            warn "Waybar missing. Installing stock..."
            exe pacman -Syu --noconfirm --needed waybar
        fi

    else
        warn "No packages selected to install."
    fi
else
    warn "niri-applist.txt not found."
fi

# ==============================================================================
# STEP 6: Dotfiles
# ==============================================================================
section "Step 5/9" "Deploying Dotfiles"

REPO_GITHUB="https://github.com/SHORiN-KiWATA/ShorinArchExperience-ArchlinuxGuide.git"
REPO_GITEE="https://gitee.com/shorinkiwata/ShorinArchExperience-ArchlinuxGuide.git"
TEMP_DIR="/tmp/shorin-repo"

rm -rf "$TEMP_DIR"
log "Cloning configuration repository..."

# Attempt 1: GitHub
if runuser -u "$TARGET_USER" -- git clone "$REPO_GITHUB" "$TEMP_DIR"; then
    success "Cloned successfully (Source: GitHub)."
else
    warn "GitHub clone failed. Attempting fallback to Gitee..."
    rm -rf "$TEMP_DIR"
    
    # Attempt 2: Gitee
    if runuser -u "$TARGET_USER" -- git clone "$REPO_GITEE" "$TEMP_DIR"; then
        success "Cloned successfully (Source: Gitee)."
    else
        error "Clone failed from both GitHub and Gitee."
        # Clone failure triggers the handler
        critical_failure_handler "Failed to clone dotfiles from GitHub and Gitee."
    fi
fi

if [ -d "$TEMP_DIR/dotfiles" ]; then
    UID1000_USER=$(id -nu 1000 2>/dev/null)
    if [ "$UID1000_USER" != "shorin" ]; then
        rm -f "$TEMP_DIR/dotfiles/.config/gtk-3.0/bookmarks"
    fi

    BACKUP_NAME="config_backup_$(date +%s).tar.gz"
    log "Backing up..."
    exe runuser -u "$TARGET_USER" -- tar -czf "$HOME_DIR/$BACKUP_NAME" -C "$HOME_DIR" .config
    
    log "Applying..."
    exe runuser -u "$TARGET_USER" -- cp -rf "$TEMP_DIR/dotfiles/." "$HOME_DIR/"

    log "Fixing GTK 4.0 symlinks..."
    GTK4_CONF="$HOME_DIR/.config/gtk-4.0"
    THEME_SRC="$HOME_DIR/.themes/adw-gtk3-dark/gtk-4.0"

    exe runuser -u "$TARGET_USER" -- rm -rfv "$GTK4_CONF/assets" "$GTK4_CONF/gtk.css" "$GTK4_CONF/gtk-dark.css"
    exe runuser -u "$TARGET_USER" -- ln -sf "$THEME_SRC/gtk-dark.css" "$GTK4_CONF/gtk-dark.css"
    exe runuser -u "$TARGET_USER" -- ln -sf "$THEME_SRC/gtk.css" "$GTK4_CONF/gtk.css"
    exe runuser -u "$TARGET_USER" -- ln -sf "$THEME_SRC/assets" "$GTK4_CONF/assets"

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

# ==============================================================================
# STEP 7: Wallpapers
# ==============================================================================
section "Step 6/9" "Wallpapers"
WALL_DEST="$HOME_DIR/Pictures/Wallpapers"
if [ -d "$TEMP_DIR/wallpapers" ]; then
    exe runuser -u "$TARGET_USER" -- mkdir -p "$WALL_DEST"
    exe runuser -u "$TARGET_USER" -- cp -rf "$TEMP_DIR/wallpapers/." "$WALL_DEST/"
    success "Installed."
fi
rm -rf "$TEMP_DIR"

# ==============================================================================
# STEP 8: Hardware Tools
# ==============================================================================
section "Step 7/9" "Hardware"
# exe runuser -u "$TARGET_USER" -- yay -Syu --noconfirm --needed ddcutil-service
gpasswd -a "$TARGET_USER" i2c
# exe pacman -Syu --noconfirm --needed swayosd
systemctl enable --now swayosd-libinput-backend.service > /dev/null 2>&1
success "Tools configured."

# ==============================================================================
# STEP 9: Cleanup
# ==============================================================================
section "Step 9/9" "Cleanup"
rm -f "$SUDO_TEMP_FILE"
success "Done."

# ==============================================================================
# STEP 10: Auto-Login
# ==============================================================================
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

# ==============================================================================
# STEP 11: Completion
# ==============================================================================

# Disable trap to avoid false positives during exit
trap - ERR

log "Module 04 completed."