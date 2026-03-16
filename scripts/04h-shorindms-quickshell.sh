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
VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST" # 确保每次运行生成全新的订单

# --- Identify User & DM Check ---
log "Identifying target user..."
detect_target_user

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
    error "Target user invalid or home directory does not exist."
    exit 1
fi

info_kv "Target User" "$TARGET_USER"

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

# --- Installation: Core Components ---
AUR_HELPER="paru"
section "Shorin DMS" "Core Components"
log "Installing core shell components..."

QS_PKG="quickshell"
DMS_PKG="dms-shell-bin"

# 2. 检测环境变量，按需切换为 git 版
if [[ "${SHORIN_DMS_GIT:-0}" == "1" ]]; then
    log "Environment SHORIN_DMS_GIT=1 detected. Using git packages..."
    QS_PKG="quickshell-git"
    # DMS_PKG="dms-shell-git"
else
    log "Using pre-compiled stable packages..."
fi

log "Installing core shell components..."

# 3. 组合包列表并执行安装
CORE_PKGS="$QS_PKG $DMS_PKG niri xwayland-satellite kitty xdg-desktop-portal-gnome niri-sidebar-git nwg-look cava cliphist wl-clipboard dgop dsearch-bin qt5-multimedia polkit-gnome satty mpv cups-pk-helper kimageformats"

echo "$CORE_PKGS" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed $CORE_PKGS

# --- Dotfiles & Wallpapers ---
section "Shorin DMS" "Dotfiles & Wallpapers"
log "Deploying user dotfiles..."
DOTFILES_SRC="$PARENT_DIR/dms-dotfiles"
chown -R "$TARGET_USER:" "$DOTFILES_SRC"
force_copy "$DOTFILES_SRC/." "$HOME_DIR"

log "Deploying wallpapers..."
WALLPAPER_SOURCE_DIR="$PARENT_DIR/resources/Wallpapers"
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"
chown -R "$TARGET_USER:" "$WALLPAPER_SOURCE_DIR"
as_user mkdir -p "$WALLPAPER_DIR"
force_copy "$WALLPAPER_SOURCE_DIR/." "$WALLPAPER_DIR/"

# --- File Manager & Terminal Setup ---
section "Shorin DMS" "File Manager & Terminal"

log "Installing Nautilus, Thunar and dependencies..."
FM_PKGS1="ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus"
FM_PKGS2="xdg-desktop-portal-gtk thunar tumbler ffmpegthumbnailer poppler-glib gvfs-smb file-roller thunar-archive-plugin gnome-keyring thunar-volman gvfs-mtp gvfs-gphoto2 webp-pixbuf-loader libgsf"

echo "$FM_PKGS1" >> "$VERIFY_LIST"
echo "$FM_PKGS2" >> "$VERIFY_LIST"

exe pacman -S --noconfirm --needed $FM_PKGS1
exe as_user "$AUR_HELPER" -S --noconfirm --needed $FM_PKGS2

log "Installing terminal utilities..."
TERM_PKGS="xdg-terminal-exec fuzzel wf-recorder wl-screenrec-git ttf-jetbrains-maple-mono-nf-xx-xx eza zoxide starship jq fish libnotify timg imv cava imagemagick wl-clipboard cliphist shorin-contrib-git"

echo "$TERM_PKGS" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed $TERM_PKGS

# shorin-contrib
as_user shorin link

log "Configuring default terminal and templates..."
# 默认终端处理
if ! grep -q "kitty" "$HOME_DIR/.config/xdg-terminals.list"; then
    echo 'kitty.desktop' >> "$HOME_DIR/.config/xdg-terminals.list"
fi

# if [ ! -f /usr/local/bin/gnome-terminal ] || [ -L /usr/local/bin/gnome-terminal ]; then
#   exe ln -sf /usr/bin/kitty /usr/local/bin/gnome-terminal
# fi
sudo -u "$TARGET_USER" dbus-run-session gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty

as_user mkdir -p "$HOME_DIR/Templates"
as_user touch "$HOME_DIR/Templates/new" "$HOME_DIR/Templates/new.sh"
as_user bash -c "echo '#!/usr/bin/env bash' >> '$HOME_DIR/Templates/new.sh'"
chown -R "$TARGET_USER:" "$HOME_DIR/Templates"

log "Applying Nautilus bugfixes and bookmarks..."
configure_nautilus_user
as_user sed -i "s/shorin/$TARGET_USER/g" "$HOME_DIR/.config/gtk-3.0/bookmarks"

# --- Flatpak & Theme Integration ---
section "Shorin DMS" "Flatpak & Theme Integration"

if command -v flatpak &>/dev/null; then
    log "Configuring Flatpak overrides and themes..."
    echo "bazaar" >> "$VERIFY_LIST"
    exe as_user "$AUR_HELPER" -S --noconfirm --needed bazaar
    as_user flatpak override --user --filesystem=xdg-data/themes
    as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
    as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
    as_user flatpak override --user --filesystem=xdg-config/gtk-3.0
    as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    as_user flatpak override --user --filesystem=xdg-config/fontconfig
    as_user ln -sf /usr/share/themes "$HOME_DIR/.local/share/themes"
fi

# === update module ===
if command -v kitty &>/dev/null; then
    exe ln -sf /usr/bin/kitty /usr/local/bin/xterm
fi

log "Installing theme components and browser..."
THEME_PKGS="matugen adw-gtk-theme python-pywalfox firefox nwg-look"
echo "$THEME_PKGS" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed $THEME_PKGS

log "Configuring Firefox Pywalfox policy..."
POL_DIR="/etc/firefox/policies"
exe mkdir -p "$POL_DIR"
echo '{ "policies": { "Extensions": { "Install": ["https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"] } } }' >"$POL_DIR/policies.json"
exe chmod 755 "$POL_DIR"
exe chmod 644 "$POL_DIR/policies.json"

# --- Desktop Cleanup & Tutorials ---
section "Config" "Desktop Cleanup"
log "Hiding unnecessary .desktop icons..."
run_hide_desktop_file

log "Copying tutorial files..."
force_copy "$PARENT_DIR/resources/必看-Shorin-DMS-Niri使用方法.txt" "$HOME_DIR"

# niri blur toggle 脚本
curl -L shorin.xyz/niri-blur-toggle | as_user bash

# --- Finalization & Auto-Login ---
section "Final" "Auto-Login & Cleanup"
rm -f "$SUDO_TEMP_FILE"

# 1. 清理旧的 TTY 自动登录残留（无论是否启用 greetd，旧版残留都应清除）
log "Cleaning up legacy TTY autologin configs..."
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null

if [ "$SKIP_DM" = true ]; then
    log "Display Manager setup skipped (Conflict found or user opted out)."
    warn "You will need to start your session manually from the TTY."
else
    
    setup_ly
fi