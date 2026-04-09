#!/bin/bash
# 04c-quickshell-setup.sh

# 1. 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found in $SCRIPT_DIR."
    exit 1
fi

VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"

log "Installing iNiR..."
# ==============================================================================
#  Identify User & DM Check
# ==============================================================================
log "Identifying user..."
detect_target_user

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
    error "Target user invalid or home directory does not exist."
    exit 1
fi

info_kv "Target" "$TARGET_USER"

# DM Check
check_dm_conflict

# --- Temporary Sudo Privileges ---
log "Granting temporary sudo privileges..."
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

cleanup_sudo() {
    if [[ -f "$SUDO_TEMP_FILE" ]]; then
        rm -f "$SUDO_TEMP_FILE"
        log "Security: Temporary sudo privileges revoked."
    fi
}
trap cleanup_sudo EXIT INT TERM



log "Target user for iNiR installation: $TARGET_USER"

# 下载并执行安装脚本
INSTALLER_DIR="/tmp/inir_install.sh"
INIR_URL="https://github.com/snowarch/inir.git"

log "Downloading iNiR installer wrapper..."
if git clone --depth 1 "$INIR_URL" "$INSTALLER_DIR"; then
    
    chmod +x "$INSTALLER_DIR/setup"
    chown "$TARGET_USER" "$INSTALLER_DIR"
    
    log "Executing iNiR installer as user ($TARGET_USER)..."
    log "NOTE: If the installer asks for input, this script might hang."
    if as_user bash -c "cd ~ && $INSTALLER_DIR/setup install -y"; then
        log "iNiR installation process completed successfully."
    else
        warn "iNiR installer returned an error code. You may need to install it manually."
        exit 1
    fi
else
    warn "Failed to download iNiR installer script from $INIR_URL."
fi

# ====verify =====

INIR_INSTALLED="false"

if command -v niri &>/dev/null; then
    INIR_INSTALLED="true"
else
    warn "iNiR (niri) command not found after installation. Please verify manually."
    exit 1
fi


# ==============================================================================
#  autosatrt
# ==============================================================================
INIR_CONFIG_DIR="$HOME_DIR/.config/niri/config.d"
INIR_AUTOSTART_CONFIG="$INIR_CONFIG_DIR/50-startup.kdl"
INIR_ENV_CONFIG="$INIR_CONFIG_DIR/40-environment.kdl"

if ! grep -q "+si:localuser:root" "$INIR_AUTOSTART_CONFIG"; then
    log "Enabling DMS autostart in niri config.kdl..."
    echo 'spawn-at-startup "xhost" "+si:localuser:root"' >> "$INIR_AUTOSTART_CONFIG"
    echo 'spawn-at-startup "inir" "run"' >> "$INIR_AUTOSTART_CONFIG"
fi


# ==============================================================================
#  fcitx5 configuration and locale
# ==============================================================================
section "Config" "input method"

as_user paru -S --noconfirm --needed fcitx5-im fcitx5-rime rime-ice-git fcitx5-configtool

if ! grep -q "fcitx5" "$INIR_AUTOSTART_CONFIG"; then
    log "Enabling fcitx5 autostart in niri config.kdl..."
    echo 'spawn-at-startup "fcitx5" "-d"' >> "$INIR_AUTOSTART_CONFIG"
else
    log "Fcitx5 autostart already exists, skipping."
fi

if grep -q "^[[:space:]]*environment[[:space:]]*{" "$INIR_ENV_CONFIG"; then
    log "Existing environment block found. Injecting fcitx variables..."
    if ! grep -q 'XMODIFIERS "@im=fcitx"' "$INIR_ENV_CONFIG"; then
        sed -i '/^[[:space:]]*environment[[:space:]]*{/a \    LC_CTYPE "en_US.UTF-8"\n    XMODIFIERS "@im=fcitx"\n    LANG "zh_CN.UTF-8"    \nLANGUAGE "zh_CN.UTF-8"' "$INIR_ENV_CONFIG"
    else
        log "Environment variables for fcitx already exist, skipping."
    fi
fi

chown -R "$TARGET_USER:" "$PARENT_DIR/quickshell-dotfiles"

force_copy "$PARENT_DIR/quickshell-dotfiles/." "$HOME_DIR/"

# ==============================================================================
# filemanager
# ==============================================================================
section "Config" "file manager"

FM_PKGS="ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal  xdg-terminal-exec file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus"
echo "$FM_PKGS" >> "$VERIFY_LIST"
exe as_user paru -S --noconfirm --needed $FM_PKGS
# 默认终端处理
if ! grep -q "kitty" "$HOME_DIR/.config/xdg-terminals.list"; then
    echo 'kitty.desktop' >> "$HOME_DIR/.config/xdg-terminals.list"
fi

sudo -u "$TARGET_USER" dbus-run-session gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty

as_user mkdir -p "$HOME_DIR/Templates"
as_user touch "$HOME_DIR/Templates/new"
as_user touch "$HOME_DIR/Templates/new.sh"
if [[ -f "$HOME_DIR/Templates/new.sh" ]] && grep -q "#!" "$HOME_DIR/Templates/new.sh"; then
    log "Template new.sh already initialized."
else
    as_user bash -c "echo '#!/usr/bin/env bash' >> '$HOME_DIR/Templates/new.sh'"
fi
chown -R "$TARGET_USER:" "$HOME_DIR/Templates"
configure_nautilus_user

# ==============================================================================
#  screenshare
# ==============================================================================
section "Config" "screenshare"

echo "xdg-desktop-portal-gnome" >> "$VERIFY_LIST"
exe pacman -S --noconfirm --needed xdg-desktop-portal-gnome
if ! grep -q '/usr/lib/xdg-desktop-portal-gnome' "$INIR_AUTOSTART_CONFIG"; then
    log "Configuring environment in niri config.kdl"
    echo 'spawn-sh-at-startup "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=niri & /usr/lib/xdg-desktop-portal-gnome"' >> "$DMS_NIRI_CONFIG_FILE"
fi

run_hide_desktop_file

# ==============================================================================
#  Dispaly Manager
# ==============================================================================
section "Config" "Dispaly Manager"

log "Cleaning up legacy TTY autologin configs..."
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null

if [ "$SKIP_DM" = true ]; then
    log "Display Manager setup skipped (Conflict found or user opted out)."
    warn "You will need to start your session manually from the TTY."
else
    setup_ly
fi

log "Module 04c completed."