#!/bin/bash
# 04c-quickshell-setup.sh

# 1. 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found in $SCRIPT_DIR."
    exit 1
fi

# ==============================================================================
#  核心辅助函数定义
# ==============================================================================

# --- 函数：强制安全拷贝（解决覆盖冲突） ---
force_copy() {
    local src="$1"
    local target_dir="$2"
    
    if [[ -z "$src" || -z "$target_dir" ]]; then
        warn "force_copy: Missing arguments"
        return 1
    fi
    
    local item_name
    item_name=$(basename "$src")
    
    # 只有当拷贝的不是 "目录下的所有内容" (即路径不以 /. 结尾) 时，才执行精确删除
    if [[ "$src" != */. ]]; then
        # 清理 target_dir 结尾多余的斜杠或 /.
        local clean_target="${target_dir%/}"
        clean_target="${clean_target%/.}"
        
        # 先安全删除目标路径的同名内容，防止目录覆盖文件的冲突
        as_user rm -rf "${clean_target}/${item_name}"
    fi
    
    # 执行安全拷贝
    exe as_user cp -rf "$src" "$target_dir"
}

# --- 函数：静默删除 niri 绑定 ---
niri_remove_bind() {
    local target_key="$1"
    local config_file="$HOME_DIR/.config/niri/dms/binds.kdl"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    # 使用 Python 处理，无日志，无备份
    python3 -c "
import sys, re

file_path = '$config_file'
target_key = sys.argv[1]

try:
    with open(file_path, 'r') as f:
        content = f.read()

    pattern = re.compile(r'(?m)^\s*(?!//).*?' + re.escape(target_key) + r'(?=\s|\{)')

    while True:
        match = pattern.search(content)
        if not match:
            break

        start_idx = match.start()
        open_brace_idx = content.find('{', start_idx)
        if open_brace_idx == -1:
            break

        balance = 0
        end_idx = -1
        for i in range(open_brace_idx, len(content)):
            char = content[i]
            if char == '{':
                balance += 1
            elif char == '}':
                balance -= 1
                if balance == 0:
                    end_idx = i + 1
                    break

        if end_idx != -1:
            if end_idx < len(content) and content[end_idx] == '\n':
                end_idx += 1
            content = content[:start_idx] + content[end_idx:]
        else:
            break

    with open(file_path, 'w') as f:
        f.write(content)

except Exception:
    pass
    " "$target_key"
}

VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"

log "Installing DMS..."
# ==============================================================================
#  Identify User & DM Check
# ==============================================================================
log "Identifying user..."
detect_target_user

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
    error "Target user invalid or home directory does not exist."
    exit 1
fi

info_kv "Target" "$TARGET_USER"

# DM Check
check_dm_conflict

log "Target user for DMS installation: $TARGET_USER"

# 下载并执行安装脚本
INSTALLER_SCRIPT="/tmp/dms_install.sh"
DMS_URL="https://install.danklinux.com"

log "Downloading DMS installer wrapper..."
if curl -fsSL "$DMS_URL" -o "$INSTALLER_SCRIPT"; then
    chmod +x "$INSTALLER_SCRIPT"
    chown "$TARGET_USER" "$INSTALLER_SCRIPT"
    
    log "Executing DMS installer as user ($TARGET_USER)..."
    log "NOTE: If the installer asks for input, this script might hang."
    pacman -S --noconfirm vulkan-headers
    if runuser -u "$TARGET_USER" -- bash -c "cd ~ && $INSTALLER_SCRIPT"; then
        success "DankMaterialShell installed successfully."
    else
        warn "DMS installer returned an error code. You may need to install it manually."
        exit 1
    fi
    rm -f "$INSTALLER_SCRIPT"
else
    warn "Failed to download DMS installer script from $DMS_URL."
fi


# ==============================================================================
#  dms 随图形化环境自动启动
# ==============================================================================
section "Config" "dms autostart"

DMS_AUTOSTART_LINK="$HOME_DIR/.config/systemd/user/niri.service.wants/dms.service"
DMS_NIRI_CONFIG_FILE="$HOME_DIR/.config/niri/config.kdl"
DMS_HYPR_CONFIG_FILE="$HOME_DIR/.config/hypr/hyprland.conf"

if [[ -L "$DMS_AUTOSTART_LINK" ]]; then
    log "Detect DMS systemd service enabled, disabling ...."
    rm -f "$DMS_AUTOSTART_LINK"
fi

DMS_NIRI_INSTALLED="false"
DMS_HYPR_INSTALLED="false"

if command -v niri &>/dev/null; then
    DMS_NIRI_INSTALLED="true"
    elif command -v hyprland &>/dev/null; then
    DMS_HYPR_INSTALLED="true"
fi

if [[ "$DMS_NIRI_INSTALLED" == "true" ]]; then
    if ! grep -E -q "^[[:space:]]*spawn-at-startup.*dms.*run" "$DMS_NIRI_CONFIG_FILE"; then
        log "Enabling DMS autostart in niri config.kdl..."
        echo 'spawn-at-startup "dms" "run"' >> "$DMS_NIRI_CONFIG_FILE"
        echo 'spawn-at-startup "xhost" "+si:localuser:root"' >> "$DMS_NIRI_CONFIG_FILE"
    else
        log "DMS autostart already exists in niri config.kdl, skipping."
    fi
    
    elif [[ "$DMS_HYPR_INSTALLED" == "true" ]]; then
    log "Configuring Hyprland autostart..."
    if ! grep -q "exec-once.*dms run" "$DMS_HYPR_CONFIG_FILE"; then
        log "Adding DMS autostart to hyprland.conf"
        echo 'exec-once = dms run' >> "$DMS_HYPR_CONFIG_FILE"
        echo 'exec-once = xhost +si:localuser:root'>> "$DMS_HYPR_CONFIG_FILE"
    else
        log "DMS autostart already exists in Hyprland config, skipping."
    fi
fi

# ==============================================================================
#  fcitx5 configuration and locale
# ==============================================================================
section "Config" "input method"

if [[ "$DMS_NIRI_INSTALLED" == "true" ]]; then
    if ! grep -q "fcitx5" "$DMS_NIRI_CONFIG_FILE"; then
        log "Enabling fcitx5 autostart in niri config.kdl..."
        echo 'spawn-at-startup "fcitx5" "-d"' >> "$DMS_NIRI_CONFIG_FILE"
    else
        log "Fcitx5 autostart already exists, skipping."
    fi
    
    if grep -q "^[[:space:]]*environment[[:space:]]*{" "$DMS_NIRI_CONFIG_FILE"; then
        log "Existing environment block found. Injecting fcitx variables..."
        if ! grep -q 'XMODIFIERS "@im=fcitx"' "$DMS_NIRI_CONFIG_FILE"; then
            sed -i '/^[[:space:]]*environment[[:space:]]*{/a \    LC_CTYPE "en_US.UTF-8"\n    XMODIFIERS "@im=fcitx"\n    LANG "zh_CN.UTF-8"' "$DMS_NIRI_CONFIG_FILE"
        else
            log "Environment variables for fcitx already exist, skipping."
        fi
    else
        log "No environment block found. Appending new block..."
        cat << EOT >> "$DMS_NIRI_CONFIG_FILE"

environment {
    LC_CTYPE "en_US.UTF-8"
    XMODIFIERS "@im=fcitx"
    LANGUAGE "zh_CN.UTF-8"
    LANG "zh_CN.UTF-8"
}
EOT
    fi
    
    chown -R "$TARGET_USER:" "$PARENT_DIR/quickshell-dotfiles"
    
    # === [ 核心修复点 ] ===
    # 精准清除目标路径中会导致冲突的非目录文件(软链接)
    as_user rm -rf "$HOME_DIR/.local/share/fcitx5"
    as_user rm -rf "$HOME_DIR/.config/fcitx5"
    # =======================
    
    force_copy "$PARENT_DIR/quickshell-dotfiles/." "$HOME_DIR/"
    
    elif [[ "$DMS_HYPR_INSTALLED" == "true" ]]; then
    if ! grep -q "fcitx5" "$DMS_HYPR_CONFIG_FILE"; then
        log "Adding fcitx5 autostart to hyprland.conf"
        echo 'exec-once = fcitx5 -d' >> "$DMS_HYPR_CONFIG_FILE"
        
        cat << EOT >> "$DMS_HYPR_CONFIG_FILE"

# --- Added by Shorin-Setup Script ---
# Fcitx5 Input Method Variables
env = XMODIFIERS,@im=fcitx
env = LC_CTYPE,en_US.UTF-8
# Locale Settings
env = LANG,zh_CN.UTF-8
# ----------------------------------
EOT
    else
        log "Fcitx5 configuration already exists in Hyprland config, skipping."
    fi
    
    chown -R "$TARGET_USER:" "$PARENT_DIR/quickshell-dotfiles"
    
    # === [ 核心修复点 ] ===
    as_user rm -rf "$HOME_DIR/.local/share/fcitx5"
    as_user rm -rf "$HOME_DIR/.config/fcitx5"
    # 这里我顺手修正了原本脚本的一个小 Bug:
    # 如果 quickshell-dotfiles 包含 .config 和 .local，应复制到 ~ 下，而不是 ~/.config/ 下，否则会变成 ~/.config/.config
    force_copy "$PARENT_DIR/quickshell-dotfiles/." "$HOME_DIR/"
fi
# ==============================================================================
# filemanager
# ==============================================================================
section "Config" "file manager"

if [[ "$DMS_NIRI_INSTALLED" == "true" ]]; then
    log "DMS niri detected, configuring nautilus"
    FM_PKGS="ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal  xdg-terminal-exec file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus"
    echo "$FM_PKGS" >> "$VERIFY_LIST"
    exe as_user paru -S --noconfirm --needed $FM_PKGS
    # 默认终端处理
    if ! grep -q "kitty" "$HOME_DIR/.config/xdg-terminals.list"; then
        echo 'kitty.desktop' >> "$HOME_DIR/.config/xdg-terminals.list"
    fi
    
    # if [ ! -f /usr/local/bin/gnome-terminal ] || [ -L /usr/local/bin/gnome-terminal ]; then
    #   exe ln -sf /usr/bin/kitty /usr/local/bin/gnome-terminal
    # fi
    sudo -u "$TARGET_USER" dbus-run-session gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty
    
    as_user mkdir -p "$HOME_DIR/Templates"
    as_user touch "$HOME_DIR/Templates/new"
    as_user touch "$HOME_DIR/Templates/new.sh"
    as_user bash -c "echo '#!/bin/bash' >> '$HOME_DIR/Templates/new.sh'"
    chown -R "$TARGET_USER:" "$HOME_DIR/Templates"
    
    configure_nautilus_user
    
    
    elif [[ "$DMS_HYPR_INSTALLED" == "true" ]]; then
    log "DMS hyprland detected, skipping file manager."
fi

# ==============================================================================
#  screenshare
# ==============================================================================
section "Config" "screenshare"

if [[ "$DMS_NIRI_INSTALLED" == "true" ]]; then
    log "DMS niri detected, configuring xdg-desktop-portal"
    echo "xdg-desktop-portal-gnome" >> "$VERIFY_LIST"
    exe pacman -S --noconfirm --needed xdg-desktop-portal-gnome
    if ! grep -q '/usr/lib/xdg-desktop-portal-gnome' "$DMS_NIRI_CONFIG_FILE"; then
        log "Configuring environment in niri config.kdl"
        echo 'spawn-sh-at-startup "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=niri & /usr/lib/xdg-desktop-portal-gnome"' >> "$DMS_NIRI_CONFIG_FILE"
    fi
    
    elif [[ "$DMS_HYPR_INSTALLED" == "true" ]]; then
    log "DMS hyprland detected, configuring xdg-desktop-portal"
    echo "xdg-desktop-portal-hyprland" >> "$VERIFY_LIST"
    exe pacman -S --noconfirm --needed xdg-desktop-portal-hyprland
    if ! grep -q '/usr/lib/xdg-desktop-portal-hyprland' "$DMS_HYPR_CONFIG_FILE"; then
        log "Configuring environment in hyprland.conf"
        echo 'exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=hyprland & /usr/lib/xdg-desktop-portal-hyprland' >> "$DMS_HYPR_CONFIG_FILE"
    fi
fi

# ==============================================================================
#  Validation Check: DMS & Core Components (Blackbox Audit)
# ==============================================================================
section "Config" "components validation"
log "Verifying DMS and core components installation..."

MISSING_COMPONENTS=()

if ! command -v dms &>/dev/null ; then
    MISSING_COMPONENTS+=("dms")
fi
if ! command -v quickshell &>/dev/null; then
    MISSING_COMPONENTS+=("quickshell")
fi

if [[ ${#MISSING_COMPONENTS[@]} -gt 0 ]]; then
    error "FATAL: Official DMS installer failed to provide core binaries!"
    warn "Missing core commands: ${MISSING_COMPONENTS[*]}"
    write_log "FATAL" "DMS Blackbox installation failed. Missing: ${MISSING_COMPONENTS[*]}"
    echo -e "   ${H_YELLOW}>>> Exiting installer. Please check upstream DankLinux repo or network. ${NC}"
    exit 1
else
    success "Blackbox components validated successfully."
fi

# ==============================================================================
#  Dispaly Manager
# ==============================================================================
section "Config" "Dispaly Manager"

log "Cleaning up legacy TTY autologin configs..."
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null

if [ "$SKIP_DM" = true ]; then
    log "Display Manager setup skipped (Conflict found or user opted out)."
    warn "You will need to start your session manually from the TTY."
else
    setup_ly
fi

log "Module 04c completed."