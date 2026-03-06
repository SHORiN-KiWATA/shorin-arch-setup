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


# 安装验证
VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"

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

# =======================================================================
# exec
# =======================================================================

# === dotfiles ===
section "Minimal Niri" "Dotfiles"
force_copy "$PARENT_DIR/minimal-niri-dotfiles/." "$HOME_DIR"

# === bookmark ===
BOOKMARKS_FILE="$HOME_DIR/.config/gtk-3.0/bookmarks"
if [ -f "$BOOKMARKS_FILE" ]; then
    as_user sed -i "s/shorin/$TARGET_USER/g" "$BOOKMARKS_FILE"
fi
# === niri output.kdl ===
OUTPUT_EXAMPLE_KDL="$HOME_DIR/.config/niri/output-example.kdl"
OUTPUT_KDL="$HOME_DIR/.config/niri/output.kdl"
if [ "$TARGET_USER" != "shorin" ]; then
    as_user touch $OUTPUT_KDL
else
    as_user cp "$DOTFILES_REPO/dotfiles/.config/niri/output-example.kdl" "$OUTPUT_KDL"
fi

# == core ===
AUR_HELPER="paru"

section "Minimal Niri" "Core Components"
NIRI_PKGS="niri xwayland-satellite xdg-desktop-portal-gnome fuzzel waybar polkit-gnome mako "
echo "$NIRI_PKGS" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed "$NIRI_PKGS"

# === terminal ===
section "Minimal Niri" "Terminal"
TERMINAL_PKGS="zsh foot ttf-jetbrains-maple-mono-nf-xx-xx starship eza zoxide"
echo "$TERMINAL_PKGS" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed "$TERMINAL_PKGS"


# === filemanager ===
section "Minimal Niri" "File Manager"
FM_PKGS1="ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus"
FM_PKGS2="xdg-desktop-portal-gtk thunar tumbler ffmpegthumbnailer poppler-glib gvfs-smb file-roller thunar-archive-plugin gnome-keyring thunar-volman gvfs-mtp gvfs-gphoto2 webp-pixbuf-loader libgsf"
echo "$FM_PKGS1" >> "$VERIFY_LIST"
echo "$FM_PKGS2" >> "$VERIFY_LIST"
exe pacman -S --noconfirm --needed $FM_PKGS1
exe pacman -S --noconfirm --needed $FM_PKGS2
echo "xdg-terminal-exec" >> "$VERIFY_LIST"
exe as_user paru -S --noconfirm --needed xdg-terminal-exec
if grep -q "foot" "$HOME_DIR/.config/xdg-terminals.list"; then
    echo 'foot.desktop' >> "$HOME_DIR/.config/xdg-terminals.list"
fi
sudo -u "$TARGET_USER" dbus-run-session gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal foot
configure_nautilus_user



# === tools ===
section "Minimal Niri" "Tools"
TOOLS_PKGS="imv cliphist wl-clipboard shorinclip-git shorin-contrib-git hyprlock breeze-cursors"
echo "$TOOLS_PKGS" >> "$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed $TOOLS_PKGS
as_user shorin link


# === flatpak ===
if command -v flatpak &>/dev/null; then
    as_user flatpak override --user --filesystem=xdg-data/themes
    as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
    as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
    as_user flatpak override --user --filesystem=xdg-config/gtk-3.0
    as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    as_user flatpak override --user --filesystem=xdg-config/fontconfig
fi