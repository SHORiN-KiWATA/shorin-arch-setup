#!/bin/bash

# ==============================================================================
# 04-niri-setup.sh - Niri Desktop (Visual Enhanced)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}

check_root

# --- Helper: Local Fallback (FIXED) ---
install_local_fallback() {
    local pkg_name="$1"
    local search_dir="$PARENT_DIR/compiled/$pkg_name"
    if [ ! -d "$search_dir" ]; then return 1; fi

    # [FIX] 使用 mapfile 读取所有匹配的包文件到数组，而不是只取第一个
    mapfile -t pkg_files < <(find "$search_dir" -maxdepth 1 -name "*.pkg.tar.zst")

    if [ ${#pkg_files[@]} -gt 0 ]; then
        warn "Using local fallback for '$pkg_name' (Found ${#pkg_files[@]} files)..."

        # [FIX] 1. 遍历所有找到的包，收集所有依赖
        log "Resolving dependencies for local packages..."
        local all_deps=""
        
        for pkg_file in "${pkg_files[@]}"; do
            # 从每个包的 .PKGINFO 中提取依赖
            local deps=$(tar -xOf "$pkg_file" .PKGINFO | grep -E '^depend' | cut -d '=' -f 2 | xargs)
            if [ -n "$deps" ]; then
                all_deps="$all_deps $deps"
            fi
        done
        
        # [FIX] 2. 统一安装依赖
        if [ -n "$all_deps" ]; then
            # 简单的去重处理 (虽然 yay 也能处理重复，但这样日志更好看)
            local unique_deps=$(echo "$all_deps" | tr ' ' '\n' | sort -u | tr '\n' ' ')
            log "Dependencies found: $unique_deps"
            
            # 安装依赖
            if ! exe runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --asdeps $unique_deps; then
                error "Failed to install dependencies for local package '$pkg_name'."
                return 1
            fi
        fi

        log "Dependencies met. Installing all local packages..."
        
        # [FIX] 3. 一次性安装目录下所有的包文件
        # "${pkg_files[@]}" 会正确展开为多个参数传递给 yay
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
PKGS="niri xdg-desktop-portal xdg-desktop-portal-gtk fuzzel kitty firefox libnotify mako polkit-gnome pciutils"
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
default=gtk
org.freedesktop.impl.portal.ScreenCast=gnome;gtk
org.freedesktop.impl.portal.Screenshot=gnome;gtk
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
# 3. Network Optimization (Updated Mirror Menu)
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
    
    # 调用通用函数来选择镜像
    select_flathub_mirror
    
    # Disable P2P for stability
    exe flatpak remote-modify --no-p2p flathub
    
    export GOPROXY=https://goproxy.cn,direct
    if ! grep -q "GOPROXY" /etc/environment; then echo "GOPROXY=https://goproxy.cn,direct" >> /etc/environment; fi
    exe runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
    success "Optimizations Enabled."
else
    log "Using Global Sources."
fi

log "Configuring temporary sudo access..."
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

# ------------------------------------------------------------------------------
# 4. Dependencies
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

        # 根据中文环境标志，重排安装列表
        if [ "$IS_CN_ENV" = true ]; then
            log "CN environment detected. Prioritizing local packages."
        fi
        
        # Batch
        if [ -n "$BATCH_LIST" ]; then
            log "Batch Install..."
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

        # Git
        if [ ${#GIT_LIST[@]} -gt 0 ]; then
            log "Git Install..."
            for git_pkg in "${GIT_LIST[@]}"; do
                # --- 新逻辑：CN 环境本地优先 ---
                if [ "$IS_CN_ENV" = true ]; then
                    log "Attempting local install for '$git_pkg'..."
                    if install_local_fallback "$git_pkg"; then
                        success "Installed $git_pkg from local cache."
                        continue # 安装成功，跳过网络安装
                    else
                        log "Local package not found. Proceeding with network install..."
                    fi
                fi

                # --- 标准网络安装流程 (作为回退或默认) ---
                # 尝试 1: 正常网络安装
                if exe runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                    success "Installed $git_pkg"
                else
                    # 尝试 2: 切换镜像后重试
                    warn "Network install failed for $git_pkg. Retrying with mirror toggle..."
                    if runuser -u "$TARGET_USER" -- git config --global --get url."https://gitclone.com/github.com/".insteadOf > /dev/null; then
                        runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
                    else
                        runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
                    fi

                    if exe runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                        success "Installed $git_pkg (on retry)."
                    else
                        # 尝试 3: 如果不是CN环境，最后尝试本地回退
                        if [ "$IS_CN_ENV" = false ]; then
                            warn "Final attempt: Checking local cache for $git_pkg..."
                            if install_local_fallback "$git_pkg"; then
                                success "Installed $git_pkg from local cache (fallback)."
                            else
                                error "Failed to install '$git_pkg' after all attempts."
                                FAILED_PACKAGES+=("$git_pkg")
                            fi
                        else
                            # CN环境下，本地安装已在最开始尝试过
                            error "Failed to install '$git_pkg' after all attempts."
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
            printf "%s\n" "${FAILED_PACKAGES[@]}" > "$REPORT_FILE"
            chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
            warn "Some packages failed. See: $REPORT_FILE"
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