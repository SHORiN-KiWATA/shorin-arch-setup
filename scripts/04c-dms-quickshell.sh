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
KNOWN_DMS=("gdm" "sddm" "lightdm" "lxdm" "slim" "xorg-xdm" "ly" "greetd")
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
elif command -v hyprland &/dev/null; then
    DMS_HYPR_INSTALLED=true
fi

# 修改niri配置文件设置dms自动启动
if [ $DMS_NIRI_INSTALLED = true ]; then

    if ! grep -E -q "^[[:space:]]*spawn-at-startup.*dms.*run" "$HOME_DIR/.config/niri/config.kdl"; then
        log "enabling dms autostart in niri config.kdl..." 
        echo 'spawn-at-startup "dmr" "run"' >> "$HOME_DIR/.config/niri/config.kdl"
    else
        log "dms autostart already exists in niri config.kdl, skipping."
    fi

# 修改hyprland的配置文件设置dms自动启动
elif [ $DMS_HYPR_INSTALLED = true ]; then

    true

fi
# ==============================================================================
#  tty autologin
# ==============================================================================
section "Config" "tty autostart"

SVC_DIR="$HOME_DIR/.config/systemd/user"
SVC_FILE="$SVC_DIR/niri-autostart.service"
LINK="$SVC_DIR/default.target.wants/niri-autostart.service"

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

    cat <<EOT >"$SVC_FILE"
[Unit]
Description=Hyprland DMS Session Autostart
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