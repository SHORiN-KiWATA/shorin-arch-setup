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
# 专门剥开一层目录打软链接的辅助函数
link_subdir() {
    local sub_dir="$1"     # 例如 ".config" 或 ".local/bin"
    local src_base="$2"    # 仓库里的 dotfiles 路径
    local target_base="$3" # 用户的 Home 目录
    
    local full_src="$src_base/$sub_dir"
    local full_target="$target_base/$sub_dir"
    
    if [[ -d "$full_src" ]]; then
        # 确保用户的目标容器目录（如 ~/.config）存在
        as_user mkdir -p "$full_target"
        
        # 遍历源目录里的具体项目（如 niri, kitty）
        shopt -s dotglob
        for item in "$full_src"/*; do
            [ -e "$item" ] || continue
            local item_name=$(basename "$item")
            
            # 暴力清除目标位置的旧文件夹或旧软链
            as_user rm -rf "$full_target/$item_name" 2>/dev/null
            
            # 神仙参数组合: -s(建立软链) -n(目标是软链时视为文件直接覆盖) -f(强制)
            as_user ln -snf "$item" "$full_target/$item_name"
        done
        shopt -u dotglob
    fi
}

# 聚合管理函数
link_dotfiles() {
    local src="$1"
    local target="$2"
    
    # 你可以在这里指定要链接哪些顶层目录，绝不会误伤系统其他配置
    link_subdir ".config" "$src" "$target"
    link_subdir ".local/bin" "$src" "$target"
    link_subdir ".local/share" "$src" "$target"
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

# --- Dotfiles & Wallpapers ---
section "Shorin DMS" "Dotfiles & Wallpapers"

SHORIN_DMS_REPO="$HOME_DIR/.local/share/shorin-dms"

log "Setting up Shorin DMS Git Repository..."
if [[ ! -d "$SHORIN_DMS_REPO/.git" ]]; then
    as_user mkdir -p "$HOME_DIR/.local/share/shorin-dms"
    # 直接将包含 .git 的安装仓库完整拷贝过去，免网络克隆
    exe cp -rf "$PARENT_DIR/." "$SHORIN_DMS_REPO"
    
    # 修正所有权，让目标用户接管仓库
    chown -R "$TARGET_USER:" "$SHORIN_DMS_REPO"
    as_user git config --global --add safe.directory "$SHORIN_DMS_REPO"
    log "Repository copied locally to $SHORIN_DMS_REPO"
else
    log "Repository already exists at $SHORIN_DMS_REPO, pulling latest..."
    as_user git -C "$SHORIN_DMS_REPO" config pull.rebase true
    as_user git -C "$SHORIN_DMS_REPO" add .
    as_user git -C "$SHORIN_DMS_REPO" commit -m "chore: auto-save local DMS changes" >/dev/null 2>&1 || true
    as_user git -C "$SHORIN_DMS_REPO" pull origin main -X theirs || true
fi

log "Deploying user dotfiles via Symlinks..."
DOTFILES_SRC="$SHORIN_DMS_REPO/dms-dotfiles"

# 核心：调用刚才写的软链函数！
link_dotfiles "$DOTFILES_SRC" "$HOME_DIR"

# 这个涉及到系统全局命令，依然需要 root 权限物理复制
cp -f "$DOTFILES_SRC/.local/bin/quickload" "/usr/local/bin/quickload"

log "Deploying wallpapers..."
WALLPAPER_SOURCE_DIR="$SHORIN_DMS_REPO/resources/Wallpapers"
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"

# 壁纸也可以直接整个目录软链过去，以后存新壁纸直接进 Git 仓库
as_user mkdir -p "$HOME_DIR/Pictures"
as_user rm -rf "$WALLPAPER_DIR" 2>/dev/null
as_user ln -snf "$WALLPAPER_SOURCE_DIR" "$WALLPAPER_DIR"




AUR_HELPER="paru"
# --- File Manager & Terminal Setup ---
section "Shorin DMS" "File Manager & Terminal"

log "Installing Nautilus, Thunar and dependencies..."
exe pacman -S --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus
exe as_user "$AUR_HELPER" -S --noconfirm --needed xdg-desktop-portal-gtk thunar tumbler ffmpegthumbnailer poppler-glib gvfs-smb file-roller thunar-archive-plugin gnome-keyring thunar-volman gvfs-mtp gvfs-gphoto2 webp-pixbuf-loader libgsf

log "Installing terminal utilities..."
exe as_user "$AUR_HELPER" -S --noconfirm --needed fuzzel wf-recorder ttf-jetbrains-maple-mono-nf-xx-xx eza zoxide starship jq fish libnotify timg imv cava imagemagick wl-clipboard cliphist 

log "Configuring default terminal and templates..."
ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
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
    exe as_user "$AUR_HELPER" -S --noconfirm --needed bazaar
    as_user flatpak override --user --filesystem=xdg-data/themes
    as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
    as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
    as_user flatpak override --user --filesystem=xdg-config/gtk-3.0
    as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    as_user flatpak override --user --filesystem=xdg-config/fontconfig
    as_user ln -sf /usr/share/themes "$HOME_DIR/.local/share/themes"
fi

log "Installing theme components and browser..."
exe as_user "$AUR_HELPER" -S --noconfirm --needed matugen adw-gtk-theme python-pywalfox firefox

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

SVC_DIR="$HOME_DIR/.config/systemd/user"
SVC_FILE="$SVC_DIR/niri-autostart.service"
LINK="$SVC_DIR/default.target.wants/niri-autostart.service"

if [ "$SKIP_AUTOLOGIN" = true ]; then
    log "Auto-login skipped."
    as_user rm -f "$LINK" "$SVC_FILE"
else
    log "Configuring TTY Auto-login for Niri..."
    mkdir -p "/etc/systemd/system/getty@tty1.service.d"
    echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}" >"/etc/systemd/system/getty@tty1.service.d/autologin.conf"

    as_user mkdir -p "$(dirname "$LINK")"
    cat <<EOT >"$SVC_FILE"
[Unit]
Description=Niri Session Autostart
After=graphical-session-pre.target
[Service]
ExecStart=/usr/bin/niri-session
Restart=on-failure
[Install]
WantedBy=default.target
EOT
    as_user ln -sf "../niri-autostart.service" "$LINK"
    chown -R "$TARGET_USER" "$SVC_DIR"
    success "Auto-login enabled successfully."
fi