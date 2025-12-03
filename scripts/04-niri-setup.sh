#!/bin/bash

# ==============================================================================
# 04-niri-setup.sh - Niri Desktop (Visual Enhanced & Logic Fix)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}

check_root

# --- Helper: Local Fallback (Fixed: Multiple files & Dependencies) ---
install_local_fallback() {
    local pkg_name="$1"
    local search_dir="$PARENT_DIR/compiled/$pkg_name"
    if [ ! -d "$search_dir" ]; then return 1; fi

    # 读取目录下所有包文件
    mapfile -t pkg_files < <(find "$search_dir" -maxdepth 1 -name "*.pkg.tar.zst")

    if [ ${#pkg_files[@]} -gt 0 ]; then
        warn "Using local fallback for '$pkg_name' (Found ${#pkg_files[@]} files)..."
        warn "Note: This uses cached binaries. If the app crashes, please rebuild from source."

        # 1. 收集依赖
        log "Resolving dependencies for local packages..."
        local all_deps=""
        for pkg_file in "${pkg_files[@]}"; do
            local deps=$(tar -xOf "$pkg_file" .PKGINFO | grep -E '^depend' | cut -d '=' -f 2 | xargs)
            if [ -n "$deps" ]; then all_deps="$all_deps $deps"; fi
        done
        
        # 2. 安装依赖 (使用 -Syu 确保系统同步)
        if [ -n "$all_deps" ]; then
            local unique_deps=$(echo "$all_deps" | tr ' ' '\n' | sort -u | tr '\n' ' ')
            # [UPDATE] Changed yay -S to yay -Syu
            if ! exe runuser -u "$TARGET_USER" -- yay -Syu --noconfirm --needed --asdeps $unique_deps; then
                error "Failed to install dependencies for local package '$pkg_name'."
                return 1
            fi
        fi

        # 3. 批量安装
        log "Installing local packages..."
        if exe runuser -u "$TARGET_USER" -- yay -U --noconfirm "${pkg_files[@]}"; then
            success "Installed from local."; return 0
        else
            error "Local install failed."; return 1
        fi
    else
        return 1
    fi
}

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
# 1.1 Configure Portals
# ------------------------------------------------------------------------------
log "Configuring XDG Desktop Portals..."
PORTAL_CONF_DIR="$HOME_DIR/.config/xdg-desktop-portal"
exe runuser -u "$TARGET_USER" -- mkdir -p "$PORTAL_CONF_DIR"
cat <<EOT > "/tmp/niri-portals.conf"
[preferred]
default=gnome;
EOT
exe cp "/tmp/niri-portals.conf" "$PORTAL_CONF_DIR/niri-portals.conf"
exe chown "$TARGET_USER:$TARGET_USER" "$PORTAL_CONF_DIR/niri-portals.conf"
success "Portal configured."

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
# 4. Dependencies (LOGIC REWRITE: Network First -> Local Fallback)
# ------------------------------------------------------------------------------
section "Step 4/9" "Dependencies"
LIST_FILE="$PARENT_DIR/niri-applist.txt"
FAILED_PACKAGES=()

if [ -f "$LIST_FILE" ]; then
    mapfile -t PACKAGE_ARRAY < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | tr -d '\r')
    if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
        BATCH_LIST=""
        GIT_LIST=()
        for pkg in "${PACKAGE_ARRAY[@]}"; do
            [ "$pkg" == "imagemagic" ] && pkg="imagemagick"
            if [[ "$pkg" == *"-git" || "$pkg" == "clipse-gui" ]]; then GIT_LIST+=("$pkg"); else BATCH_LIST+="$pkg "; fi
        done

        # Phase 1: Batch Install (Repository Packages)
        if [ -n "$BATCH_LIST" ]; then
            log "Batch Install..."
            # [UPDATE] Ensuring -Syu
            if ! exe runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
                warn "Batch failed. Retrying..."
                if runuser -u "$TARGET_USER" -- git config --global --get url."https://gitclone.com/github.com/".insteadOf > /dev/null; then
                    runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
                else
                    runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
                fi
                if ! exe runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
                    error "Batch failed."
                else
                    success "Batch installed."
                fi
            fi
        fi

        # Phase 2: Git/AUR Packages (Priority: Build from Source)
        if [ ${#GIT_LIST[@]} -gt 0 ]; then
            log "Git/AUR Install..."
            for git_pkg in "${GIT_LIST[@]}"; do
                log "Installing '$git_pkg' (Network Build)..."
                
                # [UPDATE] Ensuring -Syu
                if exe runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                    success "Installed $git_pkg (Built from source)."
                else
                    warn "Network build failed for '$git_pkg'."
                    warn "Retrying with mirror toggle..."
                    
                    if runuser -u "$TARGET_USER" -- git config --global --get url."https://gitclone.com/github.com/".insteadOf > /dev/null; then
                        runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
                    else
                        runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
                    fi

                    # [UPDATE] Ensuring -Syu
                    if exe runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                        success "Installed $git_pkg (Built from source - Retry)."
                    else
                        # --- Fallback: Try Local Cache ---
                        warn "Network failed. Attempting local fallback for '$git_pkg'..."
                        if install_local_fallback "$git_pkg"; then
                            warn "INSTALLED FROM LOCAL CACHE. If '$git_pkg' fails to launch, you must rebuild it manually."
                        else
                            error "Failed to install '$git_pkg' (Both Network and Local failed)."
                            FAILED_PACKAGES+=("$git_pkg")
                        fi
                    fi
                fi
            done
        fi
        
        # Recovery
        if ! command -v waybar &> /dev/null; then
            warn "Waybar missing. Installing stock..."
            exe pacman -Syu --noconfirm --needed waybar
        fi

        if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
            DOCS_DIR="$HOME_DIR/Documents"
            REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"
            if [ ! -d "$DOCS_DIR" ]; then runuser -u "$TARGET_USER" -- mkdir -p "$DOCS_DIR"; fi
            
            echo "--- Installation Failed Report $(date) ---" >> "$REPORT_FILE"
            printf "%s\n" "${FAILED_PACKAGES[@]}" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
            warn "Some packages failed. List saved to: $REPORT_FILE"
        fi
    fi
else
    warn "niri-applist.txt not found."
fi

# ------------------------------------------------------------------------------
# 5. Dotfiles
# ------------------------------------------------------------------------------
section "Step 5/9" "Deploying Dotfiles"
REPO_URL="https://github.com/SHORiN-KiWATA/ShorinArchExperience-ArchlinuxGuide.git"
TEMP_DIR="/tmp/shorin-repo"
rm -rf "$TEMP_DIR"

log "Cloning..."
if ! exe runuser -u "$TARGET_USER" -- git clone "$REPO_URL" "$TEMP_DIR"; then
    warn "Retrying clone..."
    if runuser -u "$TARGET_USER" -- git config --global --get url."https://gitclone.com/github.com/".insteadOf > /dev/null; then
        runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
    else
        runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
    fi
    if ! exe runuser -u "$TARGET_USER" -- git clone "$REPO_URL" "$TEMP_DIR"; then error "Clone failed."; fi
fi

if [ -d "$TEMP_DIR/dotfiles" ]; then
    BACKUP_NAME="config_backup_$(date +%s).tar.gz"
    log "Backing up..."
    exe runuser -u "$TARGET_USER" -- tar -czf "$HOME_DIR/$BACKUP_NAME" -C "$HOME_DIR" .config
    log "Applying..."
    exe runuser -u "$TARGET_USER" -- cp -rf "$TEMP_DIR/dotfiles/." "$HOME_DIR/"
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
runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
sed -i '/GOPROXY=https:\/\/goproxy.cn,direct/d' /etc/environment
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
    exe chown -R "$TARGET_USER:$TARGET_USER" "$HOME_DIR/.config/systemd"
    success "Enabled."
fi

log "Module 04 completed."