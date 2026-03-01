#!/bin/bash

# ==============================================================================
#  1. Load Utilities
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

section "Start" "Installing Caelestia (Quickshell)..."

# ==============================================================================
#  2. Identify User & Display Manager Check
# ==============================================================================
log "Identifying target user..."

# Detect user ID 1000 or prompt manually
detect_target_user

info_kv "Target User" "$TARGET_USER"
info_kv "Home Dir"    "$HOME_DIR"

check_dm_conflict

# ==============================================================================
#  3. Temporary Sudo Access
# ==============================================================================
# Grant passwordless sudo temporarily for the installer to run smoothly
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Privilege escalation: Temporary passwordless sudo enabled."

cleanup_sudo() {
    if [ -f "$SUDO_TEMP_FILE" ]; then
        rm -f "$SUDO_TEMP_FILE"
        log "Security: Temporary sudo privileges revoked."
    fi
}
trap cleanup_sudo EXIT INT TERM

# ==============================================================================
#  4. Installation (Caelestia)
# ==============================================================================
section "Repo" "Cloning Caelestia Repository"

CAELESTIA_REPO="https://github.com/caelestia-dots/caelestia.git"
CAELESTIA_DIR="$HOME_DIR/.local/share/caelestia"

# Clone to .local (Caelestia uses symlinks, not direct copies)
log "Cloning repository to $CAELESTIA_DIR ..."
if [ -d $CAELESTIA_DIR ]; then
        warn "Repository clone failed or already exists. Deleting..."
        rm -rf "$CAELESTIA_DIR"
fi

if exe as_user git clone "$CAELESTIA_REPO" "$CAELESTIA_DIR"; then
    chown -R $TARGET_USER $CAELESTIA_DIR
    log "repo cloned."
fi

log "Ensuring fish shell is installed..."
exe pacman -Syu --needed --noconfirm fish

section "Install" "Running Caelestia Installer"

# Switch to user, go home, and run the installer
if as_user sh -c "cd && fish $CAELESTIA_DIR/install.fish --noconfirm"; then
    chown -R $TARGET_USER $HOME_DIR/.config
    success "Caelestia installation script completed."
fi

# ==============================================================================
#  5. Post-Configuration
# ==============================================================================
section "Config" "Locale and Input Method"

HYPR_CONFIG="$CAELESTIA_DIR/hypr/hyprland.conf"

# 5.1 Fcitx5 Configuration
if [ -f "$HYPR_CONFIG" ]; then
    if ! grep -q "fcitx5" "$HYPR_CONFIG"; then 
        log "Injecting Fcitx5 config into Hyprland..."
        echo "exec-once = fcitx5 -d" >> "$HYPR_CONFIG"
        echo "env = LC_CTYPE, en_US.UTF-8" >> "$HYPR_CONFIG"
        chown -R "$TARGET_USER:" "$PARENT_DIR/quickshell-dotfiles"
        as_user cp -rf "$PARENT_DIR/quickshell-dotfiles/." "$HOME_DIR/"
    fi

    # 5.2 Chinese Locale Check
    # Fix: Ensure grep reads from input correctly
    LOCALE_AVAILABLE=$(locale -a)
    if echo "$LOCALE_AVAILABLE" | grep -q "zh_CN.utf8" && ! grep -q "zh_CN" "$HYPR_CONFIG"; then
        log "Chinese locale detected. Configuring Hyprland environment..."
        echo "env = LANG, zh_CN.UTF-8" >> "$HYPR_CONFIG"
    fi
else
    warn "Hyprland config file not found: $HYPR_CONFIG"
fi

success "Post-configuration completed."

# ==============================================================================
#  file manager
# ==============================================================================
section "config" "file manager"

if ! command -v thunar; then

exe pacman -S --needed --noconfirm thunar tumbler ffmpegthumbnailer poppler-glib gvfs-smb file-roller thunar-archive-plugin gnome-keyring polkit-gnome

fi

# === 隐藏多余的 Desktop 图标 ===
section "Config" "Hiding useless .desktop files"
log "Hiding useless .desktop files"
run_hide_desktop_file

# ==============================================================================
#  6. dispaly manager 
# ==============================================================================
section "Config" "Display Manager"

# 1. 清理旧的 TTY 自动登录残留（无论是否启用 greetd，旧版残留都应清除）
log "Cleaning up legacy TTY autologin configs..."
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null

if [ "$SKIP_DM" = true ]; then
  log "Display Manager setup skipped (Conflict found or user opted out)."
  warn "You will need to start your session manually from the TTY."
else

  setup_greetd_tuigreet
fi

section "End" "Module 04e (Caelestia) Completed"