#!/usr/bin/env bash

# =======================================================================
# Initialization & Utilities
# =======================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found in $SCRIPT_DIR."
    exit 1
fi

check_root

# 初始化安装验证文件
VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"

# =======================================================================
# Identify User & DM Check
# =======================================================================

log "Identifying target user..."
detect_target_user

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
    error "Target user invalid or home directory does not exist."
    exit 1
fi

info_kv "Target User" "$TARGET_USER"
check_dm_conflict

# =======================================================================
# Temporary Sudo Privileges
# =======================================================================

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

# =======================================================================
# Execution Phase
# =======================================================================

AUR_HELPER="paru"

# --- 1. Dotfiles ---
section "Minimal Labwc" "Dotfiles"
force_copy "$PARENT_DIR/minimal-labwc-dotfiles/." "$HOME_DIR"

# --- 2. Bookmarks ---
BOOKMARKS_FILE="$HOME_DIR/.config/gtk-3.0/bookmarks"
if [[ -f "$BOOKMARKS_FILE" ]]; then
    as_user sed -i "s/shorin/$TARGET_USER/g" "$BOOKMARKS_FILE"
fi

# --- 4. Core Components ---
section "Minimal Labwc" "Core Components"
LABWC_PKGS=(labwc xdg-desktop-portal-wlr fuzzel waybar mako swaybg waypaper polkit-gnome wlr-randr)
echo "${LABWC_PKGS[*]}" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed "${LABWC_PKGS[@]}"

# --- 5. Terminal ---
section "Minimal Labwc" "Terminal"
TERMINAL_PKGS=(fish foot ttf-jetbrains-maple-mono-nf-xx-xx starship eza zoxide imagemagick jq bat xdg-terminal-exec)
echo "${TERMINAL_PKGS[*]}" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed "${TERMINAL_PKGS[@]}"

# --- 6. File Manager ---
section "Minimal Labwc" "File Manager"
FM_PKGS2=(xdg-desktop-portal-gtk polkit-gnome gnome-keyring thunar tumbler poppler-glib thunar-archive-plugin thunar-volman gvfs-mtp gvfs-gphoto2 webp-pixbuf-loader libgsf)
echo "${FM_PKGS1[*]}" >> "$VERIFY_LIST"
echo "${FM_PKGS2[*]}" >> "$VERIFY_LIST"

exe pacman -S --noconfirm --needed "${FM_PKGS1[@]}"
exe pacman -S --noconfirm --needed "${FM_PKGS2[@]}"

log "Deploying wallpapers..."
WALLPAPER_SOURCE_DIR="$PARENT_DIR/resources/Wallpapers"
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"
if [ -d "$WALLPAPER_SOURCE_DIR" ]; then
    as_user mkdir -p "$WALLPAPER_DIR"
    force_copy "$WALLPAPER_SOURCE_DIR/." "$WALLPAPER_DIR/"
    chown -R "$TARGET_USER:" "$WALLPAPER_DIR"
fi

# --- 7. Tools ---
section "Minimal Labwc" "Tools"
TOOLS_PKGS=(imv cliphist wl-clipboard shorinclip-git shorin-contrib-git hyprlock breeze-cursors nwg-look adw-gtk-theme pavucontrol satty grim slurp opencode)
echo "${TOOLS_PKGS[*]}" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed "${TOOLS_PKGS[@]}"

as_user shorin link

# --- 8. Flatpak Overrides ---
if command -v flatpak &>/dev/null; then
    section "Minimal Niri" "Flatpak Config"
    as_user flatpak override --user --filesystem=xdg-data/themes
    as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
    as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
    as_user flatpak override --user --filesystem=xdg-config/gtk-3.0
    as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    as_user flatpak override --user --filesystem=xdg-config/fontconfig
fi
run_hide_desktop_file

force_copy "$PARENT_DIR/resources/Minimal-Labwc使用方法.txt" "$HOME_DIR"

section "Final" "Cleanup & Boot Configuration"

log "Cleaning up legacy TTY autologin configs..."
if [ "$SKIP_DM" = true ]; then
    log "Display Manager setup skipped (Conflict found or user opted out)."
    warn "You will need to start your session manually from the TTY."
else
    setup_ly
fi
