#!/usr/bin/env bash

# --- Import Utilities ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found in $SCRIPT_DIR."
    exit 1
fi

check_root

force_copy() {
    local src="$1"
    local target_dir="$2"
    
    if [[ -z "$src" || -z "$target_dir" ]]; then
        warn "force_copy: Missing arguments"
        return 1
    fi

    if [[ -d "${src%/}" ]]; then
        (cd "$src" && find . -type d) | while read -r d; do
            as_user rm -f "$target_dir/$d" 2>/dev/null
        done
    fi

    exe as_user cp -rf "$src" "$target_dir"
}

# --- Identify User & DM Check ---
log "Identifying target user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo "$u")}"
HOME_DIR="/home/$TARGET_USER"

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
    error "Target user invalid or home directory does not exist."
    exit 1
fi

info_kv "Target User" "$TARGET_USER"

KNOWN_DMS=("gdm" "sddm" "lightdm" "lxdm" "slim" "xorg-xdm" "ly" "greetd" "plasma-login-manager")
SKIP_AUTOLOGIN="false"
DM_FOUND=""

for dm in "${KNOWN_DMS[@]}"; do
    if pacman -Q "$dm" &>/dev/null; then
        DM_FOUND="$dm"
        break
    fi
done

if [[ -n "$DM_FOUND" ]]; then
    info_kv "Conflict DM" "${H_RED}$DM_FOUND${NC}"
    SKIP_AUTOLOGIN="true"
else
    read -t 20 -p "$(echo -e "   ${H_CYAN}Enable TTY auto-login? [Y/n] (Default Y): ${NC}")" choice || true
    if [[ "${choice:-Y}" =~ ^[Yy]$ ]]; then
        SKIP_AUTOLOGIN="false"
    else
        SKIP_AUTOLOGIN="true"
    fi
fi

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

# ========================================================================
#   exec 
# ========================================================================

AUR_HELPER="paru"

# --- Installation: Core Components ---
section "Shorin Hyprniri" "Core Components & Utilities"

# 清理可能冲突的依赖
declare -a target_pkgs=(
    "hyprcursor-git"
    "hyprgraphics-git"
    "hyprland-git"
    "hyprland-guiutils-git"
    "hyprlang-git"
    "hyprlock-git"
    "hyprpicker-git"
    "hyprtoolkit-git"
    "hyprutils-git"
    "xdg-desktop-portal-hyprland-git"
)
# 2. 过滤出系统中实际已安装的包
declare -a installed_pkgs=()
for pkg in "${target_pkgs[@]}"; do
    # 使用 pacman -Qq 检查是否安装，抑制输出以保持终端干净
    if pacman -Qq "$pkg" >/dev/null 2>&1; then
        installed_pkgs+=("$pkg")
    fi
done
# 3. 只有当存在已安装的包时，才执行卸载命令
if [[ ${#installed_pkgs[@]} -gt 0 ]]; then
    exe as_user "$AUR_HELPER" -Rns --noconfirm "${installed_pkgs[@]}"
fi

log "Installing Hyprland core components..."
exe as_user "$AUR_HELPER" -S --noconfirm --needed vulkan-headers hyprland-git quickshell-git dms-shell-bin matugen cava cups-pk-helper kimageformats kitty adw-gtk-theme nwg-look breeze-cursors wl-clipboard cliphist

log "Installing terminal utilities..."
exe as_user "$AUR_HELPER" -S --noconfirm --needed fish jq zoxide socat imagemagick imv starship eza ttf-jetbrains-maple-mono-nf-xx-xx fuzzel shorin-contrib-git timg 

log "Installing file manager and dependencies..."
exe as_user "$AUR_HELPER" -S --noconfirm --needed xdg-desktop-portal-gtk thunar tumbler ffmpegthumbnailer poppler-glib gvfs-smb file-roller thunar-archive-plugin gnome-keyring thunar-volman gvfs-mtp gvfs-gphoto2 webp-pixbuf-loader

log "Installing screenshot and screencast tools..."
exe as_user "$AUR_HELPER" -S --noconfirm --needed satty grim slurp xdg-desktop-portal-hyprland

# --- Environment Configurations ---
section "Shorin Hyprniri" "Environment Configuration"

log "Configuring default terminal and templates..."
exe ln -sf /usr/bin/kitty /usr/bin/gnome-terminal

as_user mkdir -p "$HOME_DIR/Templates"
as_user touch "$HOME_DIR/Templates/new" "$HOME_DIR/Templates/new.sh"
if [[ -f "$HOME_DIR/Templates/new.sh" ]] && grep -q "#!" "$HOME_DIR/Templates/new.sh"; then
    log "Template new.sh already initialized."
else
    as_user bash -c "echo '#!/usr/bin/env bash' >> '$HOME_DIR/Templates/new.sh'"
fi
chown -R "$TARGET_USER:" "$HOME_DIR/Templates"

log "Applying file manager bookmarks..."
as_user sed -i "s/shorin/$TARGET_USER/g" "$HOME_DIR/.config/gtk-3.0/bookmarks"

# --- Dotfiles & Wallpapers ---
section "Shorin Hyprniri" "Dotfiles & Wallpapers"

log "Deploying user dotfiles from repository..."
DOTFILES_REPO_LINK="https://github.com/SHORiN-KiWATA/shorin-dms-hyprniri.git"
exe git clone --depth 1 "$DOTFILES_REPO_LINK" "$PARENT_DIR/shorin-dms-hyprniri-dotfiles"
chown -R "$TARGET_USER:" "$PARENT_DIR/shorin-dms-hyprniri-dotfiles"
force_copy "$PARENT_DIR/shorin-dms-hyprniri-dotfiles/dotfiles/." "$HOME_DIR"
as_user shorin link

log "Deploying wallpapers..."
WALLPAPER_SOURCE_DIR="$PARENT_DIR/resources/Wallpapers"
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"
chown -R "$TARGET_USER:" "$WALLPAPER_SOURCE_DIR"
as_user mkdir -p "$WALLPAPER_DIR"
force_copy "$WALLPAPER_SOURCE_DIR/." "$WALLPAPER_DIR/"

# --- Browser Setup ---
section "Shorin Hyprniri" "Browser Setup"

log "Installing Firefox and Pywalfox..."
exe as_user "$AUR_HELPER" -S --noconfirm --needed firefox python-pywalfox

log "Configuring Firefox Pywalfox extension policy..."
POL_DIR="/etc/firefox/policies"
exe mkdir -p "$POL_DIR"
echo '{ "policies": { "Extensions": { "Install": ["https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"] } } }' >"$POL_DIR/policies.json"
exe chmod 755 "$POL_DIR"
exe chmod 644 "$POL_DIR/policies.json"

# --- Flatpak & Theme Integration ---
section "Shorin Hyprniri" "Flatpak & Theme Integration"

if command -v flatpak &>/dev/null; then
    log "Configuring Flatpak overrides and theme integrations..."
    exe as_user "$AUR_HELPER" -S --noconfirm --needed bazaar
    as_user flatpak override --user --filesystem=xdg-data/themes
    as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
    as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
    as_user flatpak override --user --filesystem=xdg-config/gtk-3.0
    as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    as_user flatpak override --user --filesystem=xdg-config/fontconfig
    as_user ln -sf /usr/share/themes "$HOME_DIR/.local/share/themes"
else
    warn "Flatpak is not installed. Skipping overrides."
fi


# === update module ===
if command -v kitty &>/dev/null; then 
exe ln -sf /usr/bin/kitty /usr/local/bin/xterm
fi

# --- Desktop Cleanup & Tutorials ---
section "Config" "Desktop Cleanup"
log "Hiding unnecessary .desktop icons..."
run_hide_desktop_file

log "Copying tutorial files..."
force_copy "$PARENT_DIR/resources/必看-shoirn-hyprniri使用方法.txt" "$HOME_DIR"

# ========================================================================
#   exec-end 
# ========================================================================

# --- Finalization & Auto-Login ---
section "Final" "Auto-Login & Cleanup"
rm -f "$SUDO_TEMP_FILE"

SVC_DIR="$HOME_DIR/.config/systemd/user"
SVC_FILE="$SVC_DIR/hyprland-autostart.service"
LINK="$SVC_DIR/default.target.wants/hyprland-autostart.service"

if [ "$SKIP_AUTOLOGIN" = true ]; then
    log "Auto-login skipped."
    as_user rm -f "$LINK" "$SVC_FILE"
else
    log "Configuring TTY Auto-login for Hyprland..."
    mkdir -p "/etc/systemd/system/getty@tty1.service.d"
    echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}" >"/etc/systemd/system/getty@tty1.service.d/autologin.conf"

    as_user mkdir -p "$(dirname "$LINK")"
    cat <<EOT >"$SVC_FILE"
[Unit]
Description=Hyprland Session Autostart
After=graphical-session-pre.target
[Service]
ExecStart=/usr/bin/start-hyprland
Restart=on-failure
[Install]
WantedBy=default.target
EOT
    as_user ln -sf "../hyprland-autostart.service" "$LINK"
    chown -R "$TARGET_USER" "$SVC_DIR"
    success "Auto-login enabled successfully."
fi