#!/bin/bash
# 04c-quickshell-setup.sh

# 1. 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    
    # 清理
    rm -f "$INSTALLER_SCRIPT"

else
    warn "Failed to download DMS installer script from $DMS_URL."
fi

#auto login 

SVC_DIR="$HOME_DIR/.config/systemd/user"
SVC_FILE="$SVC_DIR/niri-autostart.service"
LINK="$SVC_DIR/default.target.wants/niri-autostart.service"

if [ "$SKIP_AUTOLOGIN" = true ]; then
    log "Auto-login skipped."
    as_user rm -f "$LINK" "$SVC_FILE"
else
    log "Configuring TTY Auto-login..."
    mkdir -p "/etc/systemd/system/getty@tty1.service.d"
    echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}" >"/etc/systemd/system/getty@tty1.service.d/autologin.conf"

    as_user mkdir -p "$(dirname "$LINK")"
    cat <<EOT >"$SVC_FILE"
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
    chown -R "$TARGET_USER" "$SVC_DIR"
    success "Enabled."
fi

#-------fcitx5--------------

log "Module 05 completed."