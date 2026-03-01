#!/bin/bash

# ==============================================================================
# GNOME Setup Script (04d-gnome.sh) - Fixed D-Bus & Extensions & Verify
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# 检查 utils 脚本
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

log "Initializing installation..."

check_root

# 初始化 Verify 列表
VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"

# ==============================================================================
#  Identify User 
# ==============================================================================
detect_target_user
TARGET_UID=$(id -u "$TARGET_USER")

info_kv "Target User" "$TARGET_USER"
info_kv "Home Dir"    "$HOME_DIR"

# ==================================
# temp sudo without passwd
# ==================================
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Temp sudo file created..."

cleanup_sudo() {
    if [ -f "$SUDO_TEMP_FILE" ]; then
        rm -f "$SUDO_TEMP_FILE"
        log "Security: Temporary sudo privileges revoked."
    fi
}

trap cleanup_sudo EXIT INT TERM

#=================================================
# Step 1: Install base pkgs
#=================================================
section "Step 1" "Install base pkgs"
log "Installing GNOME and base tools..."

GNOME_BASE_PKGS="gnome-desktop gnome-backgrounds gnome-tweaks gdm ghostty celluloid loupe gnome-control-center bazaar flatpak file-roller nautilus-python firefox nm-connection-editor pacman-contrib dnsmasq ttf-jetbrains-mono-nerd"
echo "$GNOME_BASE_PKGS" >> "$VERIFY_LIST"

if exe as_user yay -S --noconfirm --needed --answerdiff=None --answerclean=None $GNOME_BASE_PKGS; then
    
    GNOME_FM_PKGS="ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus"
    echo "$GNOME_FM_PKGS" >> "$VERIFY_LIST"
    exe pacman -S --noconfirm --needed $GNOME_FM_PKGS
    
    log "Packages installed successfully."
else
    log "Installation failed."
    return 1
fi

# start gdm 
log "Enable gdm..."
exe systemctl enable gdm

#=================================================
# Step 2: Set default terminal (修复：加入 D-Bus)
#=================================================
section "Step 2" "Set default terminal"
log "Setting GNOME default terminal to Ghostty..."

# 使用 sudo -u 切换用户，并启动临时 dbus-launch 以确保 gsettings 生效
sudo -u "$TARGET_USER" bash <<EOF
    # D-Bus Fix
    if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ]; then
        eval \$(dbus-launch --sh-syntax)
        trap "kill \$DBUS_SESSION_BUS_PID" EXIT
    fi

    gsettings set org.gnome.desktop.default-applications.terminal exec 'ghostty'
    gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e'
EOF

#=================================================
# Step 3: Set locale
#=================================================
section "Step 3" "Set locale"
log "Configuring GNOME locale for user $TARGET_USER..."
ACCOUNT_FILE="/var/lib/AccountsService/users/$TARGET_USER"
ACCOUNT_DIR=$(dirname "$ACCOUNT_FILE")
mkdir -p "$ACCOUNT_DIR"
cat > "$ACCOUNT_FILE" <<EOF
[User]
Languages=zh_CN.UTF-8
EOF

#=================================================
# Step 4: Configure Shortcuts (修复：加入 D-Bus)
#=================================================
section "Step 4" "Configure Shortcuts"
log "Configuring shortcuts..."

sudo -u "$TARGET_USER" bash <<EOF
    # ================= D-Bus Fix =================
    # 在非图形化环境修改 dconf 必须手动启动 session bus
    if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ] || [ ! -e "\${DBUS_SESSION_BUS_ADDRESS#unix:path=}" ]; then
        echo "   -> Starting temporary D-Bus session for shortcuts..."
        eval \$(dbus-launch --sh-syntax)
        trap "kill \$DBUS_SESSION_BUS_PID" EXIT
    fi
    # =============================================

    echo "   ➜ Applying shortcuts for user: $(whoami)..."

    # 1. 窗口管理
    SCHEMA="org.gnome.desktop.wm.keybindings"
    gsettings set \$SCHEMA close "['<Super>q']"
    gsettings set \$SCHEMA show-desktop "['<Super>h']"
    gsettings set \$SCHEMA toggle-fullscreen "['<Alt><Super>f']"
    gsettings set \$SCHEMA toggle-maximized "['<Super>f']"
    
    gsettings set \$SCHEMA maximize "[]"
    gsettings set \$SCHEMA minimize "[]"
    gsettings set \$SCHEMA unmaximize "[]"

    gsettings set \$SCHEMA switch-to-workspace-left "['<Shift><Super>q']"
    gsettings set \$SCHEMA switch-to-workspace-right "['<Shift><Super>e']"
    gsettings set \$SCHEMA move-to-workspace-left "['<Control><Super>q']"
    gsettings set \$SCHEMA move-to-workspace-right "['<Control><Super>e']"
    
    gsettings set \$SCHEMA switch-applications "['<Alt>Tab']"
    gsettings set \$SCHEMA switch-applications-backward "['<Shift><Alt>Tab']"
    gsettings set \$SCHEMA switch-group "['<Alt>grave']"
    gsettings set \$SCHEMA switch-group-backward "['<Shift><Alt>grave']"
    
    gsettings set \$SCHEMA switch-input-source "[]"
    gsettings set \$SCHEMA switch-input-source-backward "[]"

    # 2. Shell 全局
    SCHEMA="org.gnome.shell.keybindings"
    gsettings set \$SCHEMA screenshot "['<Shift><Control><Super>a']"
    gsettings set \$SCHEMA screenshot-window "['<Control><Super>a']"
    gsettings set \$SCHEMA show-screenshot-ui "['<Alt><Super>a']"
    
    gsettings set \$SCHEMA toggle-application-view "['<Super>g']"
    gsettings set \$SCHEMA toggle-quick-settings "['<Control><Super>s']"
    gsettings set \$SCHEMA toggle-message-tray "[]"

    # 3. 自定义快捷键
    SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
    gsettings set \$SCHEMA magnifier "['<Alt><Super>0']"
    gsettings set \$SCHEMA screenreader "[]"

    add_custom() {
        local index="\$1"
        local name="\$2"
        local cmd="\$3"
        local bind="\$4"
        
        local path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom\$index/"
        local key_schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:\$path"
        
        gsettings set "\$key_schema" name "\$name"
        gsettings set "\$key_schema" command "\$cmd"
        gsettings set "\$key_schema" binding "\$bind"
        echo "\$path"
    }
    
    # 重置列表以避免冲突
    gsettings set \$SCHEMA custom-keybindings "[]"

    P0=\$(add_custom 0 "openbrowser" "firefox" "<Super>b")
    P1=\$(add_custom 1 "openterminal" "ghostty" "<Super>t")
    P2=\$(add_custom 2 "missioncenter" "missioncenter" "<Super>grave")
    P3=\$(add_custom 3 "opennautilus" "nautilus" "<Super>e")
    P4=\$(add_custom 4 "editscreenshot" "gradia --screenshot" "<Shift><Super>s")
    P5=\$(add_custom 5 "gnome-control-center" "gnome-control-center" "<Control><Alt>s")

    CUSTOM_LIST="['\$P0', '\$P1', '\$P2', '\$P3', '\$P4', '\$P5']"
    gsettings set \$SCHEMA custom-keybindings "\$CUSTOM_LIST"
    
    echo "   ➜ Shortcuts synced successfully."
EOF

#=================================================
# Step 5: Extensions
#=================================================
section "Step 5" "Install Extensions"
log "Installing Extensions CLI..."

EXT_CLI_PKGS="gnome-extensions-cli ttf-jetbrains-maple-mono-nf-xx-xx"
echo "$EXT_CLI_PKGS" >> "$VERIFY_LIST"
sudo -u $TARGET_USER yay -S --noconfirm --needed --answerdiff=None --answerclean=None $EXT_CLI_PKGS

EXTENSION_LIST=(
    "arch-update@RaphaelRochet"
    "aztaskbar@aztaskbar.gitlab.com"
    "blur-my-shell@aunetx"
    "caffeine@patapon.info"
    "clipboard-indicator@tudmotu.com"
    "color-picker@tuberry"
    "desktop-cube@schneegans.github.com"
    "fuzzy-application-search@mkhl.codeberg.page"
    "lockkeys@vaina.lt"
    "middleclickclose@paolo.tranquilli.gmail.com"
    "steal-my-focus-window@steal-my-focus-window"
    "tilingshell@ferrarodomenico.com"
    "user-theme@gnome-shell-extensions.gcampax.github.com"
    "kimpanel@kde.org"
    "rounded-window-corners@fxgn"
    "appindicatorsupport@rgcjonas.gmail.com"
)
log "Downloading extensions..."
sudo -u $TARGET_USER gnome-extensions-cli install "${EXTENSION_LIST[@]}" 2>/dev/null

section "Step 5.2" "Enable GNOME Extensions"
# 【核心修复】：为启用扩展添加 D-Bus 支持
sudo -u "$TARGET_USER" bash <<EOF
    # D-Bus Fix
    if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ]; then
        eval \$(dbus-launch --sh-syntax)
        trap "kill \$DBUS_SESSION_BUS_PID" EXIT
    fi

    echo "   ➜ Activating extensions via gsettings (D-Bus Active)..."

    enable_extension() {
        local uuid="\$1"
        local current_list=\$(gsettings get org.gnome.shell enabled-extensions)
        
        if [[ "\$current_list" == *"\$uuid"* ]]; then
            echo "   -> Extension \$uuid already enabled."
        else
            echo "   -> Enabling extension: \$uuid"
            if [ "\$current_list" = "@as []" ]; then
                gsettings set org.gnome.shell enabled-extensions "['\$uuid']"
            else
                new_list="\${current_list%]}, '\$uuid']"
                gsettings set org.gnome.shell enabled-extensions "\$new_list"
            fi
        fi
    }

    # 数组遍历，更整洁
    declare -a ext_array=(
        "user-theme@gnome-shell-extensions.gcampax.github.com"
        "arch-update@RaphaelRochet"
        "aztaskbar@aztaskbar.gitlab.com"
        "blur-my-shell@aunetx"
        "caffeine@patapon.info"
        "clipboard-indicator@tudmotu.com"
        "color-picker@tuberry"
        "desktop-cube@schneegans.github.com"
        "fuzzy-application-search@mkhl.codeberg.page"
        "lockkeys@vaina.lt"
        "middleclickclose@paolo.tranquilli.gmail.com"
        "steal-my-focus-window@steal-my-focus-window"
        "tilingshell@ferrarodomenico.com"
        "kimpanel@kde.org"
        "rounded-window-corners@fxgn"
        "appindicatorsupport@rgcjonas.gmail.com"
    )

    for ext in "\${ext_array[@]}"; do
        enable_extension "\$ext"
    done
EOF

# 编译扩展 Schema
log "Compiling extension schemas..."
chown -R $TARGET_USER:$TARGET_USER $HOME_DIR/.local/share/gnome-shell/extensions

sudo -u "$TARGET_USER" bash <<EOF
    EXT_DIR="$HOME_DIR/.local/share/gnome-shell/extensions"
    echo "   ➜ Compiling schemas in \$EXT_DIR..."
    if [ -d "\$EXT_DIR" ]; then
        for dir in "\$EXT_DIR"/*; do
            if [ -d "\$dir/schemas" ]; then
                glib-compile-schemas "\$dir/schemas"
            fi
        done
    fi
EOF

#=================================================
# Firefox Policies
#=================================================
section "Firefox" "Configuring Firefox GNOME Integration"

FF_GNOME_PKGS="gnome-browser-connector"
echo "$FF_GNOME_PKGS" >> "$VERIFY_LIST"
exe sudo -u $TARGET_USER yay -S --noconfirm --needed --answerdiff=None --answerclean=None $FF_GNOME_PKGS

POL_DIR="/etc/firefox/policies"
exe mkdir -p "$POL_DIR"
echo '{
  "policies": {
    "Extensions": {
      "Install": [
        "https://addons.mozilla.org/firefox/downloads/latest/gnome-shell-integration/latest.xpi"
      ]
    }
  }
}' > "$POL_DIR/policies.json"
exe chmod 755 "$POL_DIR" && exe chmod 644 "$POL_DIR/policies.json"
log "Firefox policies updated."

#=================================================
# Nautilus Fix & Input Method
#=================================================
configure_nautilus_user

section "Step 6" "Input method"
log "Configure input method environment..."
if ! grep -q "fcitx" "/etc/environment" 2>/dev/null; then
    cat << EOT >> /etc/environment
XIM="fcitx"
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
XDG_CURRENT_DESKTOP=GNOME
EOT
fi

#=================================================
# Dotfiles
#=================================================
section "Dotfiles" "Deploying dotfiles"
GNOME_DOTFILES_DIR=$PARENT_DIR/gnome-dotfiles

log "Ensuring .config exists..."
sudo -u $TARGET_USER mkdir -p $HOME_DIR/.config

log "Copying dotfiles..."
if [ -d "$GNOME_DOTFILES_DIR" ]; then
    cp -rf "$GNOME_DOTFILES_DIR/." "$HOME_DIR/"
else
    warn "Dotfiles directory not found: $GNOME_DOTFILES_DIR"
fi

as_user mkdir -p "$HOME_DIR/Templates"
as_user touch "$HOME_DIR/Templates/new"
# 修复：确保 new.sh 是用户所有，且内容正确
sudo -u "$TARGET_USER" bash -c "echo '#!/usr/bin/env bash' > $HOME_DIR/Templates/new.sh"
sudo -u "$TARGET_USER" chmod +x "$HOME_DIR/Templates/new.sh"

log "Fixing permissions..."
chown -R $TARGET_USER: $HOME_DIR/.config
chown -R $TARGET_USER: $HOME_DIR/.local

if command -v flatpak &>/dev/null; then
    sudo -u "$TARGET_USER" flatpak override --user --filesystem=xdg-config/fontconfig
fi

log "Installing shell tools..."
SHELL_TOOLS_PKGS="thefuck starship eza fish zoxide jq timg imagemagick shorin-contrib-git"
echo "$SHELL_TOOLS_PKGS" >> "$VERIFY_LIST"
exe as_user paru -S --noconfirm --needed $SHELL_TOOLS_PKGS 

as_user shorin link

# === 隐藏多余的 Desktop 图标 ===
section "Config" "Hiding useless .desktop files"
log "Hiding useless .desktop files"
run_hide_desktop_file


log "Installation Complete! Please reboot."
cleanup_sudo