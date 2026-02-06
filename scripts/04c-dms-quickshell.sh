#!/bin/bash
# 04c-quickshell-setup.sh

# 1. 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi
log "installing dms..."
# ==============================================================================
#  Identify User & DM Check
# ==============================================================================
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# DM Check
KNOWN_DMS=("gdm" "sddm" "lightdm" "lxdm" "slim" "xorg-xdm" "ly" "greetd" "plasma-login-manager")
SKIP_AUTOLOGIN=false
DM_FOUND=""
for dm in "${KNOWN_DMS[@]}"; do
  if pacman -Q "$dm" &>/dev/null; then
    DM_FOUND="$dm"
    break
  fi
done

if [ -n "$DM_FOUND" ]; then
  info_kv "Conflict" "${H_RED}$DM_FOUND${NC}"
  SKIP_AUTOLOGIN=true
else
  read -t 20 -p "$(echo -e "   ${H_CYAN}Enable TTY auto-login? [Y/n] (Default Y): ${NC}")" choice || true
  [[ "${choice:-Y}" =~ ^[Yy]$ ]] && SKIP_AUTOLOGIN=false || SKIP_AUTOLOGIN=true
fi

log "Target user for DMS installation: $TARGET_USER"

# 下载并执行安装脚本
INSTALLER_SCRIPT="/tmp/dms_install.sh"
DMS_URL="https://install.danklinux.com"

log "Downloading DMS installer wrapper..."
if curl -fsSL "$DMS_URL" -o "$INSTALLER_SCRIPT"; then
    
    # 赋予执行权限
    chmod +x "$INSTALLER_SCRIPT"
    
    # 将文件所有权给用户，否则 runuser 可能会因为权限问题读不到 /tmp 下的文件
    chown "$TARGET_USER" "$INSTALLER_SCRIPT"

    log "Executing DMS installer as user ($TARGET_USER)..."
    log "NOTE: If the installer asks for input, this script might hang."
    
    # --- 关键步骤：切换用户执行 ---
    if runuser -u "$TARGET_USER" -- bash -c "cd ~ && $INSTALLER_SCRIPT"; then
        success "DankMaterialShell installed successfully."
    else
        # DMS 安装失败不应该导致整个系统安装退出，所以只警告
        warn "DMS installer returned an error code. You may need to install it manually."
    fi
    rm -f "$INSTALLER_SCRIPT"
else
    warn "Failed to download DMS installer script from $DMS_URL."
fi

# ==============================================================================
#  dms 随图形化环境自动启动
# ==============================================================================
section "Config" "dms autostart"

# dms.service 路径
DMS_AUTOSTART_LINK="$HOME_DIR/.config/systemd/user/graphical-session.target.wants/dms.service"
DMS_NIRI_CONFIG_FILE="$HOME_DIR/.config/niri/config.kdl"
DMS_HYPR_CONFIG_FILE="$HOME_DIR/.config/hypr/hyprland.conf"
# 删除dms自己的服务链接（如果有的话）
if [ -L "$DMS_AUTOSTART_LINK" ]; then
    log "detect dms systemd service enabled, disabling ...." 
    rm -f "$DMS_AUTOSTART_LINK"
fi

# 状态变量
DMS_NIRI_INSTALLED=false
DMS_HYPR_INSTALLED=false

# 检查安装的是niri还是hyprland
if command -v niri &>/dev/null; then 
    DMS_NIRI_INSTALLED=true
elif command -v hyprland &>/dev/null; then
    DMS_HYPR_INSTALLED=true
fi

# 修改niri配置文件设置dms自动启动
if [ $DMS_NIRI_INSTALLED = true ]; then

    if ! grep -E -q "^[[:space:]]*spawn-at-startup.*dms.*run" "$DMS_NIRI_CONFIG_FILE"; then
        log "enabling dms autostart in niri config.kdl..." 
        echo 'spawn-at-startup "dms" "run"' >> "$DMS_NIRI_CONFIG_FILE"
    else
        log "dms autostart already exists in niri config.kdl, skipping."
    fi

# 修改hyprland的配置文件设置dms自动启动
elif [ "$DMS_HYPR_INSTALLED" = true ]; then

    log "Configuring Hyprland autostart..."

    # 1. 配置 dms run
    # 检查文件中是否已经有 dms run 相关的 exec-once
    if ! grep -q "exec-once.*dms run" "$DMS_HYPR_CONFIG_FILE"; then
        log "Adding dms autostart to hyprland.conf"
        echo 'exec-once = dms run' >> "$DMS_HYPR_CONFIG_FILE"
    else
        log "dms autostart already exists in Hyprland config, skipping."
    fi
fi

# ==============================================================================
#  fcitx5 configuration and locale
# ==============================================================================
section "Config" "input method"

# niri的输入法配置
if [ "$DMS_NIRI_INSTALLED" = true ]; then

    # fcitx5 自动启动
    if ! grep -q "fcitx5" "$DMS_NIRI_CONFIG_FILE"; then
        log "enabling fcitx5 autostart in niri config.kdl..."
        echo 'spawn-at-startup "fcitx5" "-d"' >> "$DMS_NIRI_CONFIG_FILE"
    else
        log "fcitx5 autostart already exists, skipping."
    fi

    # 处理环境变量
    # 这里的 grep 检查是否存在 environment 块的开头
    if grep -q "^[[:space:]]*environment[[:space:]]*{" "$DMS_NIRI_CONFIG_FILE"; then
        log "Existing environment block found. Injecting fcitx variables..."
        
        # 检查是否已经写过 XMODIFIERS，防止重复插入
        if ! grep -q 'XMODIFIERS "@im=fcitx"' "$DMS_NIRI_CONFIG_FILE"; then
            # 使用 sed 在 'environment {' 这一行后面 (a)ppend 插入两行配置
            # \t 代表缩进，\n 代表换行
            sed -i '/^[[:space:]]*environment[[:space:]]*{/a \    LC_CTYPE "en_US.UTF-8"\n    XMODIFIERS "@im=fcitx"\n    LANG "zh_CN.UTF-8"' "$DMS_NIRI_CONFIG_FILE"
        else
            log "Environment variables for fcitx already exist, skipping."
        fi
        
    else
        log "No environment block found. Appending new block..."
        # 如果没有 environment 块，直接追加到底部
        cat << EOT >> "$DMS_NIRI_CONFIG_FILE"

environment {
    LC_CTYPE "en_US.UTF-8"
    XMODIFIERS "@im=fcitx"
    LANG "zh_CN.UTF-8"
}
EOT
    fi

    # 3. 复制其他配置
    cp -rf "$PARENT_DIR/quickshell-dotfiles/"* "$HOME_DIR/.config/"
    chown -R "$TARGET_USER" "$HOME_DIR/.config"


# hyprland 的输入法配置
elif [ "$DMS_HYPR_INSTALLED" = true ]; then
    
    if ! grep -q "fcitx5" "$DMS_HYPR_CONFIG_FILE"; then
        log "Adding fcitx5 autostart to hyprland.conf"
        echo 'exec-once = fcitx5 -d' >> "$DMS_HYPR_CONFIG_FILE"
        
        # 【可选但推荐】同时写入 fcitx5 需要的环境变量
        # Hyprland 的环境变量写法是 env = KEY,VALUE
        cat << EOT >> "$DMS_HYPR_CONFIG_FILE"

# --- Added by Shorin-Setup Script ---
# Fcitx5 Input Method Variables
env = XMODIFIERS,@im=fcitx
env = LC_CTYPE,en_US.UTF-8
# Locale Settings
env = LANG,zh_CN.UTF-8
# ----------------------------------
EOT

    cp -rf "$PARENT_DIR/quickshell-dotfiles/"* "$HOME_DIR/.config/"
    chown -R "$TARGET_USER" "$HOME_DIR/.config"
    else
        log "fcitx5 configuration already exists in Hyprland config, skipping."
    fi
fi
# ==============================================================================
# filemanager
# ==============================================================================
section "Config" "file manager"

if [ "$DMS_NIRI_INSTALLED" = true ]; then
    log "dms niri detected, configuring nautilus"
    exe pacman -S --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus
    as_user mkdir -p "$HOME_DIR/Templates"
    as_user touch "$HOME_DIR/Templates/new"
    as_user touch "$HOME_DIR/Templates/new.sh"
    as_user echo "#!/bin/bash" >> "$HOME_DIR/Templates/new.sh"
    chown -R "$TARGET_USER" "$HOME_DIR/Templates"
# Nautilus Nvidia/Input Fix
    configure_nautilus_user


elif [ "$DMS_HYPR_INSTALLED" = true ]; then
    log "dms hyprland detected, skipping file manager "
fi

# ==============================================================================
#  screenshare
# ==============================================================================
section "Config" "screenshare"

if [ "$DMS_NIRI_INSTALLED" = true ]; then
    log "dms niri detected, configuring xdg-desktop-portal"
    exe pacman -S --noconfirm --needed xdg-desktop-portal-gnome
    
    if ! grep -q '/usr/lib/xdg-desktop-portal-gnome' $DMS_NIRI_CONFIG_FILE; then
    log "configuring environment in niri config.kdl"
    echo 'spawn-sh-at-startup "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=niri & /usr/lib/xdg-desktop-portal-gnome"' >> $DMS_NIRI_CONFIG_FILE
    fi

elif [ "$DMS_HYPR_INSTALLED" = true ]; then
    log "dms hyprland detected, configuring xdg-desktop-portal"
    exe pacman -S --noconfirm --needed xdg-desktop-portal-hyprland
    if ! grep -q '/usr/lib/xdg-desktop-portal-hyprland' $DMS_NIRI_CONFIG_FILE; then
        log "configuring environment in hyprland.conf"
        echo 'exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=hyprland & /usr/lib/xdg-desktop-portal-hyprland' >> $DMS_NIRI_CONFIG_FILE
    fi
fi

# ==============================================================================
#  tty autologin
# ==============================================================================
section "Config" "tty autostart"

SVC_DIR="$HOME_DIR/.config/systemd/user"

# 确保目录存在
as_user mkdir -p "$SVC_DIR/default.target.wants"
# tty自动登录
if [ "$SKIP_AUTOLOGIN" = false ]; then
    log "Configuring Niri Auto-start (TTY)..."
    mkdir -p "/etc/systemd/system/getty@tty1.service.d"
    echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}" >"/etc/systemd/system/getty@tty1.service.d/autologin.conf"

fi
# ===================================================
#  window manager autostart (if don't have any of dm)
# ===================================================
section "Config" "WM autostart"
# 如果安装了niri
if [ "$SKIP_AUTOLOGIN" = false ] && [ $DMS_NIRI_INSTALLED = true ] &>/dev/null; then
    SVC_FILE="$SVC_DIR/niri-autostart.service"
    LINK="$SVC_DIR/default.target.wants/niri-autostart.service"
    # 创建niri自动登录服务
    cat <<EOT >"$SVC_FILE"
[Unit]
Description=Niri Session Autostart
After=graphical-session-pre.target
StartLimitIntervalSec=60
StartLimitBurst=3
[Service]
ExecStart=/usr/bin/niri-session
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target

EOT
    # 启用服务
    as_user ln -sf "$SVC_FILE" "$LINK"
    # 确保权限
    chown -R "$TARGET_USER" "$SVC_DIR"
    success "Niri/DMS auto-start enabled with DMS dependency."

# 如果安装了hyprland
elif [ "$SKIP_AUTOLOGIN" = false ] && [ $DMS_HYPR_INSTALLED = true ] &>/dev/null; then
        SVC_FILE="$SVC_DIR/hyprland-autostart.service"
        LINK="$SVC_DIR/default.target.wants/hyprland-autostart.service"
    cat <<EOT >"$SVC_FILE"
[Unit]
Description=Hyprland Session Autostart
After=graphical-session-pre.target
StartLimitIntervalSec=60
StartLimitBurst=3
[Service]
ExecStart=/usr/bin/start-hyprland
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target

EOT
    # 启用服务
    as_user ln -sf "$SVC_FILE" "$LINK"
    # 确保权限
    chown -R "$TARGET_USER" "$SVC_DIR"
    success "Hyprland DMS auto-start enabled with DMS dependency."

fi

log "Module 05 completed."