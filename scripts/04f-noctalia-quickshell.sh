#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

check_root

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

log "Target user for Noctalia installation: $TARGET_USER"

# ==================================
# temp sudo without passwd
# ==================================
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Temp sudo file created..."

cleanup_sudo() {
    if [ -f "$SUDO_TEMP_FILE" ]; then
        rm -f "$SUDO_TEMP_FILE"
        log "Security: Temporary sudo privileges revoked."
    fi
}
trap cleanup_sudo EXIT INT TERM
# ==============================================================================
#  install core pkgs
# ==============================================================================
CORE_PKGS=(
        "niri" 
        "xdg-desktop-portal-gnome" 
        "kitty" 
        "firefox"
        "noctalia-shell"
        "qt6-multimedia-ffmpeg"
        "polkit-gnome"
        "matugen"
)

exe as_user yay -S --noconfirm --needed --answerdiff=None --answerclean=None "${CORE_PKGS[@]}"


# ==============================================================================
#  File Manager
# ==============================================================================

# ==============================================================================
#  Dotfiles
# ==============================================================================

# ==============================================================================
#  fcitx5 configuration and locale
# ==============================================================================

# ==============================================================================
#  screenshare
# ==============================================================================

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
if [ "$SKIP_AUTOLOGIN" = false ] && command -v niri &>/dev/null; then
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
    success "Niri auto-start enabled"
fi
