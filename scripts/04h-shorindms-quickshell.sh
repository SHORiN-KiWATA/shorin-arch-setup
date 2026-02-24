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
        as_user mkdir -p "$full_target"
        
        shopt -s dotglob
        for item in "$full_src"/*; do
            [ -e "$item" ] || continue
            local item_name=$(basename "$item")
            
            as_user rm -rf "$full_target/$item_name" 2>/dev/null
            as_user ln -snf "$item" "$full_target/$item_name"
        done
        shopt -u dotglob
    fi
}

# 聚合管理函数
link_dotfiles() {
    local src="$1"
    local target="$2"
    
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


# ==============================================================================
# 新增：集中式批量软件安装 (Data-Driven App Installation)
# ==============================================================================
AUR_HELPER="paru"
section "Shorin DMS" "Software Installation"

APPLIST_FILE="$SCRIPT_DIR/dms-applist.txt"

if [[ ! -f "$APPLIST_FILE" ]]; then
    error "找不到软件列表文件: $APPLIST_FILE"
    exit 1
fi

log "正在读取并解析软件列表: $APPLIST_FILE ..."
# 提取非空行和非注释行，并把换行符替换为空格，生成一个纯净的包名字符串
PKGS=$(grep -vE "^\s*#|^\s*$" "$APPLIST_FILE" | tr '\n' ' ')

if [[ -n "$PKGS" ]]; then
    log "开始批量安装所有环境依赖与核心软件..."
    # 无需加引号，让 Bash 自动把字符串按空格展开为参数列表交给 paru
    exe as_user "$AUR_HELPER" -S --noconfirm --needed $PKGS
    success "所有软件安装完毕！"
else
    warn "软件列表为空，跳过安装步骤。"
fi


# ==============================================================================
# --- Dotfiles & Wallpapers ---
# ==============================================================================
section "Shorin DMS" "Dotfiles & Wallpapers"

SHORIN_DMS_REPO="$HOME_DIR/.local/share/shorin-dms"

log "Setting up Shorin DMS Git Repository..."
if [[ ! -d "$SHORIN_DMS_REPO/.git" ]]; then
    as_user mkdir -p "$HOME_DIR/.local/share/shorin-dms"
    exe cp -rf "$PARENT_DIR/." "$SHORIN_DMS_REPO"
    
    chown -R "$TARGET_USER:" "$SHORIN_DMS_REPO"
    as_user git config --global --add safe.directory "$SHORIN_DMS_REPO"
    log "Repository copied locally to $SHORIN_DMS_REPO"
else
    log "Repository already exists at $SHORIN_DMS_REPO, pulling latest..."
    as_user git -C "$SHORIN_DMS_REPO" config pull.rebase true
    
    # 核心修复：临时注入一个自动化身份，防止新系统因为没有 Git 身份导致 commit 失败
    as_user git -C "$SHORIN_DMS_REPO" config user.name "Shorin Auto Updater"
    as_user git -C "$SHORIN_DMS_REPO" config user.email "updater@shorin.local"
    
    as_user git -C "$SHORIN_DMS_REPO" add .
    as_user git -C "$SHORIN_DMS_REPO" commit -m "chore: auto-save local DMS changes" >/dev/null 2>&1 || true
    as_user git -C "$SHORIN_DMS_REPO" pull --rebase origin main -X theirs || true
fi

log "Deploying user dotfiles via Symlinks..."
DOTFILES_SRC="$SHORIN_DMS_REPO/dms-dotfiles"

link_dotfiles "$DOTFILES_SRC" "$HOME_DIR"
if !  [ -e "$HOME_DIR/.vimrc" ]; then
    as_user ln -sf "$SHORIN_DMS_REPO/dms-dotfiles/.vimrc" "$HOME_DIR/.vimrc"
fi 

cp -f "$DOTFILES_SRC/.local/bin/quickload" "/usr/local/bin/quickload"

log "Deploying wallpapers..."
WALLPAPER_SOURCE_DIR="$SHORIN_DMS_REPO/resources/Wallpapers"
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"

as_user mkdir -p "$HOME_DIR/Pictures"
as_user rm -rf "$WALLPAPER_DIR" 2>/dev/null
as_user ln -snf "$WALLPAPER_SOURCE_DIR" "$WALLPAPER_DIR"


# ==============================================================================
# --- File Manager & Terminal Config (仅保留配置逻辑) ---
# ==============================================================================
section "Shorin DMS" "System Configuration"

log "Configuring default terminal and templates..."
ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
as_user mkdir -p "$HOME_DIR/Templates"
as_user touch "$HOME_DIR/Templates/new" "$HOME_DIR/Templates/new.sh"
as_user bash -c "echo '#!/usr/bin/env bash' >> '$HOME_DIR/Templates/new.sh'"
chown -R "$TARGET_USER:" "$HOME_DIR/Templates"

log "Applying Nautilus bugfixes and bookmarks..."
configure_nautilus_user
as_user sed -i "s/shorin/$TARGET_USER/g" "$HOME_DIR/.config/gtk-3.0/bookmarks"


# ==============================================================================
# --- Flatpak & Theme Integration (仅保留配置逻辑) ---
# ==============================================================================
section "Shorin DMS" "Flatpak & Theme Integration"

if command -v flatpak &>/dev/null; then
    log "Configuring Flatpak overrides and themes..."
    as_user flatpak override --user --filesystem=xdg-data/themes
    as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
    as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
    as_user flatpak override --user --filesystem=xdg-config/gtk-3.0
    as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    as_user flatpak override --user --filesystem=xdg-config/fontconfig
    as_user ln -sf /usr/share/themes "$HOME_DIR/.local/share/themes"
fi

log "Configuring Firefox Pywalfox policy..."
POL_DIR="/etc/firefox/policies"
exe mkdir -p "$POL_DIR"
echo '{ "policies": { "Extensions": { "Install": ["https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"] } } }' >"$POL_DIR/policies.json"
exe chmod 755 "$POL_DIR"
exe chmod 644 "$POL_DIR/policies.json"


# ==============================================================================
# --- Desktop Cleanup & Tutorials ---
# ==============================================================================
section "Config" "Desktop Cleanup"
log "Hiding unnecessary .desktop icons..."
run_hide_desktop_file

log "Copying tutorial files..."
force_copy "$PARENT_DIR/resources/必看-Shorin-DMS-Niri使用方法.txt" "$HOME_DIR"

# niri blur toggle 脚本
curl -L shorin.xyz/niri-blur-toggle | as_user bash 


# ==============================================================================
# --- Finalization & Auto-Login ---
# ==============================================================================
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