#!/bin/bash

# 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi
log "installing dms..."

check_root
# ==============================================================================
#  Identify User 
# ==============================================================================

log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

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
# installation
#=================================================
section "Step 1" "Install base pkgs"
log "Installing GNOME ..."
if exe as_user yay -S --noconfirm --needed --answerdiff=None --answerclean=None gnome-desktop gnome-backgrounds gnome-tweaks gdm ghostty gnome-control-center gnome-software flatpak file-roller nautilus-python firefox nm-connection-editor pacman-contrib dnsmasq ttf-jetbrains-maple-mono-nf-xx-xx; then
        log "PKGS intsalled "
else
        log "Installation failed."
        return 1
fi

# start gdm 
log "Enable gdm..."
exe systemctl enable gdm

#=================================================
# set default terminal
#=================================================
section "Step 2" "Set default terminal"
log "set gnome default terminal..."
exe as_user gsettings set org.gnome.desktop.default-applications.terminal exec 'ghostty'
exe as_user gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e'

#=================================================
# locale
#=================================================
section "Step 3" "Set locale"
log "Configuring GNOME locale for user $TARGET_USER..."
ACCOUNT_FILE="/var/lib/AccountsService/users/$TARGET_USER"
ACCOUNT_DIR=$(dirname "$ACCOUNT_FILE")
# 确保目录存在
mkdir -p "$ACCOUNT_DIR"
# 设置语言为中文
cat > "$ACCOUNT_FILE" <<EOF
[User]
Languages=zh_CN.UTF-8
EOF

#=================================================
# shortcuts
#=================================================
section "Step 4" "Configure Shortcuts"
log "Configuring shortcuts.."

sudo -u "$TARGET_USER" bash <<EOF
    # 必须指定 DBUS 地址才能连接到用户会话
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus"

    echo "   ➜ Applying shortcuts from config files for user: $(whoami)..."

    # ---------------------------------------------------------
    # 1. org.gnome.desktop.wm.keybindings (窗口管理)
    # ---------------------------------------------------------
    SCHEMA="org.gnome.desktop.wm.keybindings"
    
    # 基础窗口控制
    gsettings set \$SCHEMA close "['<Super>q']"
    gsettings set \$SCHEMA show-desktop "['<Super>h']"
    gsettings set \$SCHEMA toggle-fullscreen "['<Alt><Super>f']"
    gsettings set \$SCHEMA toggle-maximized "['<Super>f']"
    
    # 清理未使用的窗口控制键 
    gsettings set \$SCHEMA maximize "[]"
    gsettings set \$SCHEMA minimize "[]"
    gsettings set \$SCHEMA unmaximize "[]"

    # 切换与移动工作区 
    gsettings set \$SCHEMA switch-to-workspace-left "['<Shift><Super>q']"
    gsettings set \$SCHEMA switch-to-workspace-right "['<Shift><Super>e']"
    gsettings set \$SCHEMA move-to-workspace-left "['<Control><Super>q']"
    gsettings set \$SCHEMA move-to-workspace-right "['<Control><Super>e']"
    
    # 切换应用/窗口 
    gsettings set \$SCHEMA switch-applications "['<Alt>Tab']"
    gsettings set \$SCHEMA switch-applications-backward "['<Shift><Alt>Tab']"
    gsettings set \$SCHEMA switch-group "['<Alt>grave']"
    gsettings set \$SCHEMA switch-group-backward "['<Shift><Alt>grave']"
    
    # 清理输入法切换快捷键
    gsettings set \$SCHEMA switch-input-source "[]"
    gsettings set \$SCHEMA switch-input-source-backward "[]"

    # ---------------------------------------------------------
    # 2. org.gnome.shell.keybindings (Shell 全局)
    # ---------------------------------------------------------
    SCHEMA="org.gnome.shell.keybindings"
    
    # 截图相关
    gsettings set \$SCHEMA screenshot "['<Shift><Control><Super>a']"
    gsettings set \$SCHEMA screenshot-window "['<Control><Super>a']"
    gsettings set \$SCHEMA show-screenshot-ui "['<Alt><Super>a']"
    
    # 界面视图
    gsettings set \$SCHEMA toggle-application-view "['<Super>g']"
    gsettings set \$SCHEMA toggle-quick-settings "['<Control><Super>s']"
    gsettings set \$SCHEMA toggle-message-tray "[]"

    # ---------------------------------------------------------
    # 3. org.gnome.settings-daemon.plugins.media-keys (媒体与自定义)
    # ---------------------------------------------------------
    SCHEMA="org.gnome.settings-daemon.plugins.media-keys"

    # 辅助功能
    gsettings set \$SCHEMA magnifier "['<Alt><Super>0']"
    gsettings set \$SCHEMA screenreader "[]"

    # --- 自定义快捷键逻辑 ---
    # 定义添加函数
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

    # 构建自定义快捷键列表 (完全对应 custom0 - custom6)
    
    P0=\$(add_custom 0 "openbrowser" "firefox" "<Super>b")
    P1=\$(add_custom 1 "openterminal" "ghostty" "<Super>t")
    P2=\$(add_custom 2 "missioncenter" "missioncenter" "<Super>grave")
    P3=\$(add_custom 3 "opennautilus" "nautilus" "<Super>e")
    P4=\$(add_custom 4 "editscreenshot" "gradia --screenshot" "<Shift><Super>s")
    P5=\$(add_custom 5 "gnome-control-center" "gnome-control-center" "<Control><Alt>s")

    # 应用列表
    CUSTOM_LIST="['\$P0', '\$P1', '\$P2', '\$P3', '\$P4', '\$P5', '\$P6']"
    gsettings set \$SCHEMA custom-keybindings "\$CUSTOM_LIST"
    
    echo "   ➜ Shortcuts synced with config files successfully."
EOF

#=================================================
# extensions
#=================================================
section "Step 5" "Install Extensions"
log "Installing Extensions..."

sudo -u $TARGET_USER yay -S --noconfirm --needed --answerdiff=None --answerclean=None gnome-extensions-cli

EXTENSION_LIST=(
    "arch-update@RaphaelRochet"
    "aztaskbar@aztaskbar.gitlab.com"
    "blur-my-shell@aunetx"
    "caffeine@patapon.info"
    "clipboard-indicator@tudmotu.com"
    "color-picker@tuberry"
    "desktop-cube@schneegans.github.com"
    "ding@rastersoft.com"
    "fuzzy-application-search@mkhl.codeberg.page"
    "lockkeys@vaina.lt"
    "middleclickclose@paolo.tranquilli.gmail.com"
    "steal-my-focus-window@steal-my-focus-window"
    "tilingshell@ferrarodomenico.com"
    "user-theme@gnome-shell-extensions.gcampax.github.com"
    "kimpanel@kde.org"
    "rounded-window-corners@fxgn"
)
log "Downloading extensions..."
sudo -u $TARGET_USER gnome-extensions-cli install ${EXTENSION_LIST[@]} 2>/dev/null

section "Step 5.2" "Enable GNOME Extensions"
sudo -u "$TARGET_USER" bash <<EOF
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus"

    # 定义一个函数来安全地启用扩展 (追加模式)
    enable_extension() {
        local uuid="\$1"
        local current_list=\$(gsettings get org.gnome.shell enabled-extensions)
        
        # 检查是否已经在列表中
        if [[ "\$current_list" == *"\$uuid"* ]]; then
            echo "   -> Extension \$uuid already enabled."
        else
            echo "   -> Enabling extension: \$uuid"
            # 如果列表为空 (@as [])，直接设置；否则追加
            if [ "\$current_list" = "@as []" ]; then
                gsettings set org.gnome.shell enabled-extensions "['\$uuid']"
            else
                # 去掉右括号，加逗号和新 uuid，再补回右括号
                # 注意：gsettings 的列表格式有点严格，这里做简单的字符串拼接
                new_list="\${current_list%]}, '\$uuid']"
                gsettings set org.gnome.shell enabled-extensions "\$new_list"
            fi
        fi
    }

    echo "   ➜ Activating extensions..."

    # 在这里列出你所有需要激活的扩展 UUID
    # (这些 UUID 通常也是你安装扩展时用的名字)
    
    enable_extension "user-theme@gnome-shell-extensions.gcampax.github.com"
    enable_extension "arch-update@RaphaelRochet"
    enable_extension "aztaskbar@aztaskbar.gitlab.com"
    enable_extension "blur-my-shell@aunetx"
    enable_extension "caffeine@patapon.info"
    enable_extension "clipboard-indicator@tudmotu.com"
    enable_extension "color-picker@tuberry"
    enable_extension "desktop-cube@schneegans.github.com"
    enable_extension "ding@rastersoft.com"
    enable_extension "fuzzy-application-search@mkhl.codeberg.page"
    enable_extension "lockkeys@vaina.lt"
    enable_extension "middleclickclose@paolo.tranquilli.gmail.com"
    enable_extension "steal-my-focus-window@steal-my-focus-window"
    enable_extension "tilingshell@ferrarodomenico.com"
    enable_extension "kimpanel@kde.org"
    enable_extension "rounded-window-corners@fxgn"

    echo "   ➜ Extensions activation request sent."
EOF

chown -R $TARGET_USER $HOME_DIR/.local/share/gnome-shell/extensions
sudo -u "$TARGET_USER" bash <<EOF
    EXT_DIR="$HOME_DIR/.local/share/gnome-shell/extensions"
    
    for dir in "\$EXT_DIR"/*; do
        if [ -d "\$dir/schemas" ]; then
            glib-compile-schemas "\$dir/schemas"
        fi
    done
EOF
# === firefox inte ===
log "Configuring Firefox GNOME Integration..."

exe sudo -u $TARGET_USER yay -S --noconfirm --needed --answerdiff=None --answerclean=None gnome-browser-connector

# 配置 Firefox 策略自动安装扩展
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
# Input Method
#=================================================
section "Step 6" "Input method"
log "Configure input method."

if ! cat "/etc/environment" | grep -q "fcitx" ; then

    cat << EOT >> /etc/environment
XIM="fcitx"
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
XDG_CURRENT_DESKTOP=GNOME
EOT

fi

#=================================================
# dotfiles
#=================================================
log "Deploying dotfiles..."
GNOME_DOTFILES_DIR=$PARENT_DIR/gnome-dotfiles
as_user mkdir -p $HOME_DIR/.config
cp -rf $GNOME_DOTFILES_DIR/. $HOME_DIR
chown -R $TARGET_USER $HOME_DIR
pacman -S --noconfirm --needed thefuck starship eza fish zoxide

log "Dotfiles deployed and shell tools installed."

