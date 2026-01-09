#!/bin/bash

# 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi
log "installing dms..."

check_root
# ==============================================================================
#  Identify User 
# ==============================================================================
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

#=================================================
# installation
#=================================================
log "Installing GNOME ..."
GNOME_PKGS="gnome-desktop gdm ghostty gnome-control-center gnome-software flatpak file-roller nautilus-python firefox "
if exe as_user yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$GNOME_PKGS"; then
        log "PKGS intsalled "
else
        log "Installation failed."
        return 1
fi

# start gdm
log "Enable gdm..."
exe systemctl enable gdm

# set default terminal
log "set gnome default terminal..."
exe gsettings set org.gnome.desktop.default-applications.terminal exec 'ghostty'
exe gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e'

