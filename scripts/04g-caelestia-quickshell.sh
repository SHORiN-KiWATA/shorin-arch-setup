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
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
HOME_DIR="/home/$TARGET_USER"

info_kv "Target User" "$TARGET_USER"
info_kv "Home Dir"    "$HOME_DIR"

# Check for conflicting Display Managers (DM)
KNOWN_DMS=("gdm" "sddm" "lightdm" "lxdm" "slim" "xorg-xdm" "ly" "greetd" "plasma-login-manager")
SKIP_AUTOLOGIN=false
DM_FOUND=""

log "Checking for existing Display Managers..."
for dm in "${KNOWN_DMS[@]}"; do
    if pacman -Q "$dm" &>/dev/null; then
        DM_FOUND="$dm"
        break
    fi
done

if [ -n "$DM_FOUND" ]; then
    info_kv "Conflict" "${H_RED}Found active DM: $DM_FOUND${NC}"
    warn "Existing Display Manager detected. TTY auto-login will be disabled."
    SKIP_AUTOLOGIN=true
else
    # Prompt user for TTY auto-login if no DM found
    echo -ne "   ${H_CYAN}Enable TTY auto-login? [Y/n] (Default Y): ${NC}"
    read -t 20 choice || true
    if [[ "${choice:-Y}" =~ ^[Yy]$ ]]; then
        SKIP_AUTOLOGIN=false
    else
        SKIP_AUTOLOGIN=true
    fi
fi

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

if exe git clone "$CAELESTIA_REPO" "$CAELESTIA_DIR"; then
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
        cp -rf $PARENT_DIR/quickshell-dotfiles/fcitx5 $HOME_DIR/.config/
        chown -R $TARGET_USER $HOME_DIR/.config/fcitx5
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

# ==============================================================================
#  6. Autostart & Autologin
# ==============================================================================
section "Config" "Systemd Autostart Setup"

SVC_DIR="$HOME_DIR/.config/systemd/user"
SVC_FILE="$SVC_DIR/hyprland-autostart.service"
LINK="$SVC_DIR/default.target.wants/hyprland-autostart.service"

# Ensure user systemd directory exists
as_user mkdir -p "$SVC_DIR/default.target.wants"

# 6.1 TTY Auto-login (System Level)
if [ "$SKIP_AUTOLOGIN" = false ]; then
    log "Configuring TTY Auto-login for $TARGET_USER..."
    
    mkdir -p "/etc/systemd/system/getty@tty1.service.d"
    # Create drop-in file for autologin
    cat <<EOF >"/etc/systemd/system/getty@tty1.service.d/autologin.conf"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}
EOF
fi

# 6.2 Hyprland User Service
if [ "$SKIP_AUTOLOGIN" = false ] && command -v hyprland &>/dev/null; then
    log "Creating Hyprland autostart service..."

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

    # Enable service via symlink
    as_user ln -sf "$SVC_FILE" "$LINK"
    
    # Fix permissions
    chown -R "$TARGET_USER" "$SVC_DIR"
    
    success "Hyprland auto-start enabled."
fi

section "End" "Module 04e (Caelestia) Completed"