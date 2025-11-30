#!/bin/bash

# ==============================================================================
# 04-niri-setup.sh - Niri Desktop, Dotfiles & User Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log ">>> Starting Phase 4: Niri Environment & Dotfiles Setup"

# ------------------------------------------------------------------------------
# 0. Identify Target User
# ------------------------------------------------------------------------------
log "Step 0/9: Identify User"

DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)

if [ -n "$DETECTED_USER" ]; then
    TARGET_USER="$DETECTED_USER"
    log "-> Automatically detected target user: $TARGET_USER"
else
    warn "Could not detect a standard user (UID 1000)."
    while true; do
        read -p "Please enter the target username: " TARGET_USER
        if id "$TARGET_USER" &>/dev/null; then
            break
        else
            warn "User '$TARGET_USER' does not exist."
        fi
    done
fi

HOME_DIR="/home/$TARGET_USER"
log "-> Installing configurations for: $TARGET_USER ($HOME_DIR)"

# ------------------------------------------------------------------------------
# [SAFETY CHECK] Detect Existing Display Managers
# ------------------------------------------------------------------------------
log "[SAFETY CHECK] Checking for active Display Managers..."

DMS=("gdm" "sddm" "lightdm" "lxdm" "ly")
SKIP_AUTOLOGIN=false

for dm in "${DMS[@]}"; do
    if systemctl is-enabled "$dm.service" &>/dev/null; then
        echo -e "${YELLOW}[INFO] Detected active Display Manager: $dm${NC}"
        echo -e "${YELLOW}[INFO] Niri will be added to the session list in $dm.${NC}"
        echo -e "${YELLOW}[INFO] TTY auto-login configuration will be SKIPPED to avoid conflicts.${NC}"
        SKIP_AUTOLOGIN=true
        break
    fi
done

if [ "$SKIP_AUTOLOGIN" = false ]; then
    log "-> No active Display Manager detected. Will configure TTY auto-login."
fi

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

pacman -S --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus > /dev/null 2>&1

# Symlink Kitty to Gnome-Terminal (Safe Mode)
if [ -f /usr/bin/gnome-terminal ] && [ ! -L /usr/bin/gnome-terminal ]; then
    warn "/usr/bin/gnome-terminal is a real file. Skipping symlink."
else
    log "-> Symlinking kitty to gnome-terminal..."
    ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
fi

# Patch Nautilus
DESKTOP_FILE="/usr/share/applications/org.gnome.Nautilus.desktop"
if [ -f "$DESKTOP_FILE" ]; then
    log "-> Patching Nautilus .desktop file..."
    sed -i 's/^Exec=/Exec=env GSK_RENDERER=gl GTK_IM_MODULE=fcitx /' "$DESKTOP_FILE"
fi

# ------------------------------------------------------------------------------
# 3. Software Store & Flatpak (With Timezone Detection)
# ------------------------------------------------------------------------------
log "Step 3/9: Configuring Software Center..."
pacman -S --noconfirm --needed flatpak gnome-software > /dev/null 2>&1

# 1. Add Flathub repo first (Official)
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# 2. Smart Mirror Configuration based on Timezone
log "-> Checking System Timezone..."

# Get timezone from symlink (Standard Arch method)
CURRENT_TZ=$(readlink -f /etc/localtime)

if [[ "$CURRENT_TZ" == *"Shanghai"* ]]; then
    log "-> Detected Timezone: ${H_GREEN}Asia/Shanghai${NC}"
    log "-> Switching Flathub to USTC Mirror for faster speed..."
    flatpak remote-modify flathub --url=https://mirrors.ustc.edu.cn/flathub
    success "Flatpak configured (USTC Mirror)."
else
    log "-> Detected Timezone: ${H_YELLOW}$CURRENT_TZ${NC} (Not Shanghai)"
    log "-> Keeping Official Flathub source."
    success "Flatpak configured (Official Source)."
fi

# ------------------------------------------------------------------------------
# [TRICK] NOPASSWD for yay
# ------------------------------------------------------------------------------
log "Configuring temporary NOPASSWD sudo access for '$TARGET_USER'..."
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

# ------------------------------------------------------------------------------
# 4. Install Dependencies
# ------------------------------------------------------------------------------
log "Step 4/9: Installing dependencies from niri-applist.txt..."

LIST_FILE="$PARENT_DIR/niri-applist.txt"
FAILED_PACKAGES=()

if [ -f "$LIST_FILE" ]; then
    mapfile -t PACKAGE_ARRAY < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | tr -d '\r')
    
    if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
        BATCH_LIST=""
        GIT_LIST=()

        for pkg in "${PACKAGE_ARRAY[@]}"; do
            if [ "$pkg" == "imagemagic" ]; then pkg="imagemagick"; fi
            
            # Logic: Try to install everything via yay (AUR or Chaotic)
            # awww-git is allowed here
            
            if [[ "$pkg" == *"-git" ]]; then
                GIT_LIST+=("$pkg")
            else
                BATCH_LIST+="$pkg "
            fi
        done
        
        # --- Phase 1: Batch Install ---
        if [ -n "$BATCH_LIST" ]; then
            log "-> [Batch] Installing standard repository packages..."
            if runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
                success "Standard packages installed."
            else
                warn "Batch install issues. Retrying one-by-one..."
                for pkg in $BATCH_LIST; do
                    if ! runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$pkg"; then
                        warn "Retry 2/2 for '$pkg'..."
                        if ! runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$pkg"; then
                             error "Failed: $pkg"
                             FAILED_PACKAGES+=("$pkg")
                        fi
                    fi
                done
            fi
        fi

        # --- Phase 2: Git Install ---
        if [ ${#GIT_LIST[@]} -gt 0 ]; then
            log "-> [Slow] Installing '-git' packages..."
            for git_pkg in "${GIT_LIST[@]}"; do
                log "-> Installing: $git_pkg ..."
                if ! runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                    warn "Retry 2/2 for '$git_pkg'..."
                    if ! runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                        error "Failed: $git_pkg"
                        FAILED_PACKAGES+=("$git_pkg")
                    fi
                else
                    success "Installed: $git_pkg"
                fi
            done
        fi
        
        # --- Recovery Phase ---
        log "Running Recovery Checks..."
        
        # Waybar Recovery
        if ! command -v waybar &> /dev/null; then
            warn "Waybar binary missing."
            log "-> Installing standard 'waybar' package..."
            pacman -S --noconfirm --needed waybar > /dev/null 2>&1 && success "Waybar recovered."
        fi

        # Awww Recovery (Local Binary Fallback)
        if ! command -v awww &> /dev/null; then
            warn "Awww binary not found (AUR install failed)."
            LOCAL_BIN_AWWW="$PARENT_DIR/bin/awww"
            LOCAL_BIN_DAEMON="$PARENT_DIR/bin/awww-daemon"
            
            if [ -f "$LOCAL_BIN_AWWW" ] && [ -f "$LOCAL_BIN_DAEMON" ]; then
                log "-> Installing awww from LOCAL BINARIES (Fallback)..."
                cp "$LOCAL_BIN_AWWW" /usr/local/bin/awww
                cp "$LOCAL_BIN_DAEMON" /usr/local/bin/awww-daemon
                chmod +x /usr/local/bin/awww /usr/local/bin/awww-daemon
                success "Awww recovered using local binaries."
            else
                warn "Local binaries missing. Will try Swaybg later."
            fi
        fi

        # Report
        if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
            DOCS_DIR="$HOME_DIR/Documents"
            REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"
            if [ ! -d "$DOCS_DIR" ]; then runuser -u "$TARGET_USER" -- mkdir -p "$DOCS_DIR"; fi
            printf "%s\n" "${FAILED_PACKAGES[@]}" > "$REPORT_FILE"
            chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
            echo -e "${RED}[ATTENTION] Failed packages list saved to: $REPORT_FILE${NC}"
        else
            success "All dependencies installed successfully!"
        fi

    else
        warn "niri-applist.txt is empty."
    fi
else
    warn "niri-applist.txt not found."
fi

# ------------------------------------------------------------------------------
# 5. Clone Dotfiles (With Retry)
# ------------------------------------------------------------------------------
log "Step 5/9: Cloning and applying dotfiles..."

REPO_URL="https://github.com/SHORiN-KiWATA/ShorinArchExperience-ArchlinuxGuide.git"
TEMP_DIR="/tmp/shorin-repo"
rm -rf "$TEMP_DIR"

log "-> Cloning repository..."
if ! runuser -u "$TARGET_USER" -- git clone "$REPO_URL" "$TEMP_DIR"; then
    warn "Git clone failed. Retrying (Attempt 2/2) in 3 seconds..."
    sleep 3
    runuser -u "$TARGET_USER" -- git clone "$REPO_URL" "$TEMP_DIR"
fi

if [ -d "$TEMP_DIR/dotfiles" ]; then
    BACKUP_NAME="config_backup_$(date +%s).tar.gz"
    log "-> [BACKUP] Backing up existing ~/.config to ~/$BACKUP_NAME..."
    runuser -u "$TARGET_USER" -- tar -czf "$HOME_DIR/$BACKUP_NAME" -C "$HOME_DIR" .config
    
    log "-> Applying new dotfiles..."
    runuser -u "$TARGET_USER" -- cp -rf "$TEMP_DIR/dotfiles/." "$HOME_DIR/"
    success "Dotfiles applied."
    
    # --- [ULTIMATE FALLBACK] Check Awww status ---
    if ! command -v awww &> /dev/null; then
        warn "Awww failed all install methods. Switching to swaybg..."
        pacman -S --noconfirm --needed swaybg > /dev/null 2>&1
        SCRIPT_PATH="$HOME_DIR/.config/scripts/niri_set_overview_blur_dark_bg.sh"
        if [ -f "$SCRIPT_PATH" ]; then
            sed -i 's/^WALLPAPER_BACKEND="awww"/WALLPAPER_BACKEND="swaybg"/' "$SCRIPT_PATH"
            success "Switched backend to swaybg."
        fi
    fi
else
    error "Failed to clone repository or 'dotfiles' directory missing."
fi

# ------------------------------------------------------------------------------
# 6. Wallpapers
# ------------------------------------------------------------------------------
log "Step 6/9: Setting up Wallpapers..."
WALL_DEST="$HOME_DIR/Pictures/Wallpapers"

if [ -d "$TEMP_DIR/wallpapers" ]; then
    runuser -u "$TARGET_USER" -- mkdir -p "$WALL_DEST"
    runuser -u "$TARGET_USER" -- cp -rf "$TEMP_DIR/wallpapers/." "$WALL_DEST/"
    success "Wallpapers installed."
fi
rm -rf "$TEMP_DIR"

# ------------------------------------------------------------------------------
# 7. DDCUtil
# ------------------------------------------------------------------------------
log "Step 7/9: Configuring ddcutil..."
runuser -u "$TARGET_USER" -- yay -S --noconfirm --needed ddcutil-service > /dev/null 2>&1
gpasswd -a "$TARGET_USER" i2c

# ------------------------------------------------------------------------------
# 8. SwayOSD
# ------------------------------------------------------------------------------
log "Step 8/9: Installing SwayOSD..."
pacman -S --noconfirm --needed swayosd > /dev/null 2>&1
systemctl enable --now swayosd-libinput-backend.service > /dev/null 2>&1

# ------------------------------------------------------------------------------
# [CLEANUP] Remove temporary configs
# ------------------------------------------------------------------------------
log "Step 9/9: Restoring configuration (Cleanup)..."

log "-> Removing temporary NOPASSWD sudo access..."
rm -f "$SUDO_TEMP_FILE"

success "Cleanup complete."

# ------------------------------------------------------------------------------
# 10. Auto-Login & Niri Autostart
# ------------------------------------------------------------------------------
log "Step 10/9: Configuring Auto-login..."

if [ "$SKIP_AUTOLOGIN" = true ]; then
    echo -e "${YELLOW}[INFO] Existing Display Manager detected. Skipping TTY auto-login setup.${NC}"
else
    # 10.1 Getty
    GETTY_DIR="/etc/systemd/system/getty@tty1.service.d"
    mkdir -p "$GETTY_DIR"
    cat <<EOT > "$GETTY_DIR/autologin.conf"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}
EOT

    # 10.2 Service File
    USER_SYSTEMD_DIR="$HOME_DIR/.config/systemd/user"
    mkdir -p "$USER_SYSTEMD_DIR"
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

    # 10.3 Manual Symlink
    log "-> Enabling niri-autostart.service (Manual Symlink)..."
    WANTS_DIR="$USER_SYSTEMD_DIR/default.target.wants"
    mkdir -p "$WANTS_DIR"
    ln -sf "../niri-autostart.service" "$WANTS_DIR/niri-autostart.service"

    # 10.4 Permission Fix
    chown -R "$TARGET_USER:$TARGET_USER" "$HOME_DIR/.config/systemd"
    
    success "TTY Auto-login configured."
fi

log ">>> Phase 4 completed. REBOOT RECOMMENDED."