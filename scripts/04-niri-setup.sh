#!/bin/bash

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log ">>> Starting Phase 4: Niri Environment & Dotfiles Setup"

# ------------------------------------------------------------------------------
# 0. Identify Target User
# ------------------------------------------------------------------------------
log "Step 0/9: Identify User"

# 尝试自动获取 UID 1000 的用户（通常是第一个创建的普通用户）
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)

if [ -n "$DETECTED_USER" ]; then
    read -p "Install configuration for user '$DETECTED_USER'? (y/n): " CONFIRM
    if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
        TARGET_USER="$DETECTED_USER"
    else
        read -p "Please enter the target username: " TARGET_USER
    fi
else
    read -p "Please enter the target username: " TARGET_USER
fi

# 验证用户是否存在
if ! id "$TARGET_USER" &>/dev/null; then
    error "User '$TARGET_USER' does not exist. Please run Phase 3 first."
    exit 1
fi
HOME_DIR="/home/$TARGET_USER"
log "-> Target user set to: $TARGET_USER ($HOME_DIR)"

# ------------------------------------------------------------------------------
# 1. Install Niri & Essentials
# ------------------------------------------------------------------------------
log "Step 1/9: Installing Niri and core components..."

pacman -S --noconfirm --needed niri xwayland-satellite xdg-desktop-portal-gnome fuzzel kitty firefox libnotify mako polkit-gnome > /dev/null 2>&1
success "Niri core packages installed."

# ------------------------------------------------------------------------------
# 2. File Manager (Nautilus) Setup
# ------------------------------------------------------------------------------
log "Step 2/9: Configuring Nautilus and Terminal..."

# Install Nautilus and plugins
pacman -S --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus > /dev/null 2>&1

# Symlink Kitty to Gnome-Terminal (Brute-force override)
if [ ! -L /usr/bin/gnome-terminal ]; then
    log "-> Symlinking kitty to gnome-terminal..."
    ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
fi

# Inject Environment Variables into Nautilus .desktop
# This fixes rendering issues (GSK) and Input Method (FCITX) for Nautilus
DESKTOP_FILE="/usr/share/applications/org.gnome.Nautilus.desktop"
if [ -f "$DESKTOP_FILE" ]; then
    log "-> Patching Nautilus .desktop file for GSK/GTK vars..."
    # Replace Exec=... with Exec=env VARS ...
    sed -i 's/^Exec=/Exec=env GSK_RENDERER=gl GTK_IM_MODULE=fcitx /' "$DESKTOP_FILE"
    success "Nautilus patched."
else
    warn "Nautilus .desktop file not found."
fi

# ------------------------------------------------------------------------------
# 3. Software Store (Flatpak & Gnome Software)
# ------------------------------------------------------------------------------
log "Step 3/9: Configuring Software Center..."

pacman -S --noconfirm --needed flatpak gnome-software > /dev/null 2>&1

# Add Flathub repo first (if not exists)
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Modify URL to SJTU Mirror
log "-> Setting Flathub mirror to SJTU..."
flatpak remote-modify flathub --url=https://mirror.sjtu.edu.cn/flathub
success "Flatpak configured."

# ------------------------------------------------------------------------------
# 4. Install Dependencies from List (AUR Support)
# ------------------------------------------------------------------------------
log "Step 4/9: Installing dependencies from niri-applist.txt..."

LIST_FILE="$PARENT_DIR/niri-applist.txt"

if [ -f "$LIST_FILE" ]; then
    # Read file content into variable, replace newlines with spaces
    PACKAGES=$(grep -vE "^\s*#" "$LIST_FILE" | tr '\n' ' ')
    
    if [ -n "$PACKAGES" ]; then
        log "-> Installing: $PACKAGES"
        # Use runuser to run yay as the non-root user
        # Note: 'yay' might ask for sudo password if it installs standard packages, 
        # but since we are running via script, ensure user has NOPASSWD or be ready to type it?
        # Actually, yay usually asks for sudo password at the end. 
        # Since we are already root, we can't run yay as root.
        
        # Method: runuser as TARGET_USER.
        runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed $PACKAGES
        success "Dependencies installed."
    else
        warn "niri-applist.txt is empty."
    fi
else
    warn "niri-applist.txt not found at $LIST_FILE"
fi

# ------------------------------------------------------------------------------
# 5. Clone Dotfiles
# ------------------------------------------------------------------------------
log "Step 5/9: Cloning and applying dotfiles..."

REPO_URL="https://github.com/SHORiN-KiWATA/ShorinArchExperience-ArchlinuxGuide.git"
TEMP_DIR="/tmp/shorin-repo"

# Clean temp dir
rm -rf "$TEMP_DIR"

log "-> Cloning repository..."
# Clone as the user to avoid permission issues later? Or clone as root then chown.
# Clone as user is safer for git credentials etc, but public repo is fine.
runuser -u "$TARGET_USER" -- git clone "$REPO_URL" "$TEMP_DIR"

if [ -d "$TEMP_DIR/dotfiles" ]; then
    log "-> Moving dotfiles to $HOME_DIR..."
    # Copy content (cp -rT copies content of source to dest)
    cp -rf "$TEMP_DIR/dotfiles/." "$HOME_DIR/"
    
    # Ensure ownership is correct
    chown -R "$TARGET_USER:$TARGET_USER" "$HOME_DIR"
    success "Dotfiles applied."
else
    error "Directory 'dotfiles' not found in cloned repo."
fi

# ------------------------------------------------------------------------------
# 6. Wallpapers
# ------------------------------------------------------------------------------
log "Step 6/9: Setting up Wallpapers..."

WALL_DEST="$HOME_DIR/Pictures/Wallpapers"

if [ -d "$TEMP_DIR/wallpapers" ]; then
    mkdir -p "$WALL_DEST"
    cp -rf "$TEMP_DIR/wallpapers/." "$WALL_DEST/"
    chown -R "$TARGET_USER:$TARGET_USER" "$HOME_DIR/Pictures"
    success "Wallpapers moved to $WALL_DEST."
else
    warn "Directory 'wallpapers' not found in cloned repo."
fi

# Clean up repo
rm -rf "$TEMP_DIR"

# ------------------------------------------------------------------------------
# 7. DDCUtil (Monitor Control)
# ------------------------------------------------------------------------------
log "Step 7/9: Configuring ddcutil..."

# Install ddcutil-service via AUR (using yay as user)
runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed ddcutil-service

# Add user to i2c group
gpasswd -a "$TARGET_USER" i2c
success "ddcutil configured and user added to i2c group."

# ------------------------------------------------------------------------------
# 8. SwayOSD (CapsLock & Media Keys)
# ------------------------------------------------------------------------------
log "Step 8/9: Installing SwayOSD..."

pacman -S --noconfirm --needed swayosd > /dev/null 2>&1
systemctl enable --now swayosd-libinput-backend.service > /dev/null 2>&1
success "SwayOSD installed and backend service enabled."

# ------------------------------------------------------------------------------
# 9. Auto-Login & Niri Autostart
# ------------------------------------------------------------------------------
log "Step 9/9: Configuring Auto-login and Niri Autostart..."

# 9.1 Getty Auto-login override
GETTY_DIR="/etc/systemd/system/getty@tty1.service.d"
mkdir -p "$GETTY_DIR"

log "-> Configuring TTY1 auto-login for '$TARGET_USER'..."
cat <<EOT > "$GETTY_DIR/autologin.conf"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}
EOT

# 9.2 User-level Systemd Service for Niri
USER_SYSTEMD_DIR="$HOME_DIR/.config/systemd/user"
# Note: mkdir as root, will chown later
mkdir -p "$USER_SYSTEMD_DIR"

log "-> Creating niri-autostart.service..."
cat <<EOT > "$USER_SYSTEMD_DIR/niri-autostart.service"
[Unit]
Description=Niri Session Autostart
After=graphical-session-pre.target

[Service]
ExecStart=/usr/bin/niri-session
Restart=on-failure

[Install]
WantedBy=default.target
EOT

# Fix permissions
chown -R "$TARGET_USER:$TARGET_USER" "$HOME_DIR/.config"

# 9.3 Enable the user service
log "-> Enabling niri-autostart.service for user..."
# We use runuser to run systemctl --user
runuser -u "$TARGET_USER" -- systemctl --user enable niri-autostart.service

success "Auto-login configuration complete."

log ">>> Phase 4 completed. REBOOT RECOMMENDED."