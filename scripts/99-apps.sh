#!/bin/bash

# ==============================================================================
# 99-apps.sh - Common Applications (FZF Menu + Split Repo/AUR + Retry Logic)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

# --- [CONFIGURATION] ---
# LazyVim 硬性依赖列表 (Moved from niri-setup)
LAZYVIM_DEPS=("neovim" "ripgrep" "fd" "ttf-jetbrains-mono-nerd" "git")

check_root

# Ensure FZF is installed
if ! command -v fzf &> /dev/null; then
    log "Installing dependency: fzf..."
    pacman -S --noconfirm fzf >/dev/null 2>&1
fi

trap 'echo -e "\n   ${H_YELLOW}>>> Operation cancelled by user (Ctrl+C). Skipping...${NC}"' INT

# ------------------------------------------------------------------------------
# 0. Identify Target User & Helper
# ------------------------------------------------------------------------------
section "Phase 5" "Common Applications"

log "Identifying target user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)

if [ -n "$DETECTED_USER" ]; then
    TARGET_USER="$DETECTED_USER"
else
    read -p "   Please enter the target username: " TARGET_USER
fi
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# Helper function for user commands
as_user() {
  runuser -u "$TARGET_USER" -- "$@"
}

# ------------------------------------------------------------------------------
# 1. List Selection & User Prompt
# ------------------------------------------------------------------------------
if [ "$DESKTOP_ENV" == "kde" ]; then
    LIST_FILENAME="kde-common-applist.txt"
else
    LIST_FILENAME="common-applist.txt"
fi
LIST_FILE="$PARENT_DIR/$LIST_FILENAME"

REPO_APPS=()
AUR_APPS=()
FLATPAK_APPS=()
FAILED_PACKAGES=()
INSTALL_LAZYVIM=false

if [ ! -f "$LIST_FILE" ]; then
    warn "File $LIST_FILENAME not found. Skipping."
    trap - INT
    exit 0
fi

if ! grep -q -vE "^\s*#|^\s*$" "$LIST_FILE"; then
    warn "App list is empty. Skipping."
    trap - INT
    exit 0
fi

echo ""
echo -e "   Selected List: ${BOLD}$LIST_FILENAME${NC}"
echo -e "   ${H_YELLOW}>>> Do you want to install common applications?${NC}"
echo -e "   ${H_CYAN}    [ENTER] = Select packages${NC}"
echo -e "   ${H_CYAN}    [N]     = Skip installation${NC}"
echo -e "   ${H_YELLOW}    [Timeout 60s] = Auto-install ALL default packages (No FZF)${NC}"
echo ""

read -t 60 -p "   Please select [Y/n]: " choice
READ_STATUS=$?

SELECTED_RAW=""

# Case 1: Timeout (Auto Install ALL)
if [ $READ_STATUS -ne 0 ]; then
    echo "" 
    warn "Timeout reached (60s). Auto-installing ALL applications from list..."
    SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed -E 's/[[:space:]]+#/\t#/')

# Case 2: User Input
else
    choice=${choice:-Y}
    if [[ "$choice" =~ ^[nN]$ ]]; then
        warn "User skipped application installation."
        trap - INT
        exit 0
    else
        clear
        echo -e "\n  Loading application list..."
        
        SELECTED_RAW=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | \
            sed -E 's/[[:space:]]+#/\t#/' | \
            fzf --multi \
                --layout=reverse \
                --border \
                --margin=1,2 \
                --prompt="Search App > " \
                --pointer=">>" \
                --marker="* " \
                --delimiter=$'\t' \
                --with-nth=1 \
                --bind 'load:select-all' \
                --bind 'ctrl-a:select-all,ctrl-d:deselect-all' \
                --info=inline \
                --header="[TAB] TOGGLE | [ENTER] INSTALL | [CTRL-D] DE-ALL | [CTRL-A] SE-ALL" \
                --preview "echo {} | cut -f2 -d$'\t' | sed 's/^# //'" \
                --preview-window=right:45%:wrap:border-left \
                --color=dark \
                --color=fg+:white,bg+:black \
                --color=hl:blue,hl+:blue:bold \
                --color=header:yellow:bold \
                --color=info:magenta \
                --color=prompt:cyan,pointer:cyan:bold,marker:green:bold \
                --color=spinner:yellow)
        
        clear
        
        if [ -z "$SELECTED_RAW" ]; then
            log "Skipping application installation (User cancelled selection)."
            trap - INT
            exit 0
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 2. Categorize Selection & Strip Prefixes (Includes LazyVim Check)
# ------------------------------------------------------------------------------
log "Processing selection..."

while IFS= read -r line; do
    raw_pkg=$(echo "$line" | cut -f1 -d$'\t' | xargs)
    [[ -z "$raw_pkg" ]] && continue

    # Check for LazyVim explicitly (Case insensitive check)
    if [[ "${raw_pkg,,}" == "lazyvim" ]]; then
        INSTALL_LAZYVIM=true
        REPO_APPS+=("${LAZYVIM_DEPS[@]}")
        info_kv "Config" "LazyVim detected" "Setup deferred to Post-Install"
        continue
    fi

    if [[ "$raw_pkg" == flatpak:* ]]; then
        clean_name="${raw_pkg#flatpak:}"
        FLATPAK_APPS+=("$clean_name")
    elif [[ "$raw_pkg" == AUR:* ]]; then
        clean_name="${raw_pkg#AUR:}"
        AUR_APPS+=("$clean_name")
    else
        REPO_APPS+=("$raw_pkg")
    fi
done <<< "$SELECTED_RAW"

info_kv "Scheduled" "Repo: ${#REPO_APPS[@]}" "AUR: ${#AUR_APPS[@]}" "Flatpak: ${#FLATPAK_APPS[@]}"

# ------------------------------------------------------------------------------
# [SETUP] GLOBAL SUDO CONFIGURATION
# ------------------------------------------------------------------------------
if [ ${#REPO_APPS[@]} -gt 0 ] || [ ${#AUR_APPS[@]} -gt 0 ]; then
    log "Configuring temporary NOPASSWD for installation..."
    SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_apps"
    echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
    chmod 440 "$SUDO_TEMP_FILE"
fi

# ------------------------------------------------------------------------------
# 3. Install Applications
# ------------------------------------------------------------------------------

# --- A. Install Repo Apps (BATCH MODE) ---
if [ ${#REPO_APPS[@]} -gt 0 ]; then
    section "Step 1/3" "Official Repository Packages (Batch)"
    
    REPO_QUEUE=()
    for pkg in "${REPO_APPS[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            log "Skipping '$pkg' (Already installed)."
        else
            REPO_QUEUE+=("$pkg")
        fi
    done

    if [ ${#REPO_QUEUE[@]} -gt 0 ]; then
        BATCH_LIST="${REPO_QUEUE[*]}"
        info_kv "Installing" "${#REPO_QUEUE[@]} packages via Pacman/Yay"
        
        if ! exe as_user yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
            error "Batch installation failed. Some repo packages might be missing."
            for pkg in "${REPO_QUEUE[@]}"; do
                FAILED_PACKAGES+=("repo:$pkg")
            done
        else
            success "Repo batch installation completed."
        fi
    else
        log "All Repo packages are already installed."
    fi
fi

# --- B. Install AUR Apps (INDIVIDUAL MODE + RETRY) ---
if [ ${#AUR_APPS[@]} -gt 0 ]; then
    section "Step 2/3" "AUR Packages (Sequential + Retry)"
    
    for app in "${AUR_APPS[@]}"; do
        if pacman -Qi "$app" &>/dev/null; then
            log "Skipping '$app' (Already installed)."
            continue
        fi


        log "Installing AUR: $app ..."
        install_success=false
        max_retries=2
        
        for (( i=0; i<=max_retries; i++ )); do
            if [ $i -gt 0 ]; then
                warn "Retry $i/$max_retries for '$app' in 3 seconds..."
                sleep 3
            fi
            
            if as_user yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "$app"; then
                install_success=true
                success "Installed $app"
                break
            else
                warn "Attempt $((i+1)) failed for $app"
            fi
        done

        if [ "$install_success" = false ]; then
            error "Failed to install $app after $((max_retries+1)) attempts."
            FAILED_PACKAGES+=("aur:$app")
        fi
    done
fi

# --- C. Install Flatpak Apps (INDIVIDUAL MODE) ---
if [ ${#FLATPAK_APPS[@]} -gt 0 ]; then
    section "Step 3/3" "Flatpak Packages (Individual)"
    
    for app in "${FLATPAK_APPS[@]}"; do
        if flatpak info "$app" &>/dev/null; then
            log "Skipping '$app' (Already installed)."
            continue
        fi

        log "Installing Flatpak: $app ..."
        if ! exe flatpak install -y flathub "$app"; then
            error "Failed to install: $app"
            FAILED_PACKAGES+=("flatpak:$app")
        else
            success "Installed $app"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 4. Environment & Additional Configs (Virt/Wine/Steam/LazyVim)
# ------------------------------------------------------------------------------
section "Post-Install" "System & App Tweaks"

# --- [NEW] Virtualization Configuration (Virt-Manager) ---
if pacman -Qi virt-manager &>/dev/null; then
  info_kv "Config" "Virt-Manager detected"
  
  # 1. 安装完整依赖
  # iptables-nft 和 dnsmasq 是默认 NAT 网络必须的
  log "Installing QEMU/KVM dependencies..."
  pacman -S --noconfirm --needed qemu-full virt-manager swtpm dnsmasq 

  # 2. 添加用户组 (需要重新登录生效)
  log "Adding $TARGET_USER to libvirt group..."
  usermod -a -G libvirt "$TARGET_USER"
  # 同时添加 kvm 和 input 组以防万一
  usermod -a -G kvm,input "$TARGET_USER"

  # 3. 开启服务
  log "Enabling libvirtd service..."
  systemctl enable --now libvirtd

  # 4. [修复] 强制设置 virt-manager 默认连接为 QEMU/KVM
  # 解决第一次打开显示 LXC 或无法连接的问题
  log "Setting default URI to qemu:///system..."
  
  # 编译 glib schemas (防止 gsettings 报错)
  glib-compile-schemas /usr/share/glib-2.0/schemas/

  # 强制写入 Dconf 配置
  # uris: 连接列表
  # autoconnect: 自动连接的列表
  as_user gsettings set org.virt-manager.virt-manager.connections uris "['qemu:///system']"
  as_user gsettings set org.virt-manager.virt-manager.connections autoconnect "['qemu:///system']"

  # 5. 配置网络 (Default NAT)
  log "Starting default network..."
  sleep 3
  virsh net-start default >/dev/null 2>&1 || warn "Default network might be already active."
  virsh net-autostart default >/dev/null 2>&1 || true
  
  # 修复虚拟机安装后的dns问题
    if systemd-detect-virt -q; then
        log "Virtual Machine environment detected."
        
        # 1. 检测是否在中国 
        if [[ $(readlink -f /etc/localtime) == *"Shanghai"* ]]; then
            # 中国：只加国内 DNS
            log "Region: China. Prepending DNS..."
            echo "nameserver 223.5.5.5" >> /etc/resolv.conf
            echo "nameserver 119.29.29.29" >> /etc/resolv.conf
        else
            # 非中国：加 Google DNS
            log "Region: Global. Appending Google DNS..."
            echo "nameserver 8.8.8.8" >> /etc/resolv.conf
            echo "nameserver 1.1.1.1" >> /etc/resolv.conf
        fi
    fi
  success "Virtualization (KVM) configured."
fi

# --- [NEW] Wine Configuration & Fonts ---
if command -v wine &>/dev/null; then
  info_kv "Config" "Wine detected"
  
  # 1. 安装 Gecko 和 Mono
  log "Ensuring Wine Gecko/Mono are installed..."
  pacman -S --noconfirm --needed wine wine-gecko wine-mono 

  # 2. 初始化 Wine (使用 wineboot -u 在后台运行，不弹窗)
  WINE_PREFIX="$HOME_DIR/.wine"
  if [ ! -d "$WINE_PREFIX" ]; then
    log "Initializing wine prefix (This may take a minute)..."
    # WINEDLLOVERRIDES prohibits popups
    as_user env WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u
    # Wait for completion
    as_user wineserver -w
  else
    log "Wine prefix already exists."
  fi

  # 3. 复制字体
  FONT_SRC="$PARENT_DIR/resources/windows-sim-fonts"
  FONT_DEST="$WINE_PREFIX/drive_c/windows/Fonts"

  if [ -d "$FONT_SRC" ]; then
    log "Copying Windows fonts from resources..."
    
    # 1. 确保目标目录存在 (以用户身份创建)
    if [ ! -d "$FONT_DEST" ]; then
        as_user mkdir -p "$FONT_DEST"
    fi

    # 2. 执行复制 (关键修改：直接以目标用户身份复制，而不是 Root 复制后再 Chown)
    # 使用 cp -rT 确保目录内容合并，而不是把源目录本身拷进去
    # 注意：这里假设 as_user 能够接受命令参数。如果 as_user 只是简单的 su/sudo 封装：
    if sudo -u "$TARGET_USER" cp -rf "$FONT_SRC"/. "$FONT_DEST/"; then
        success "Fonts copied successfully."
    else
        error "Failed to copy fonts."
    fi

    # 3. 强制刷新 Wine 字体缓存 (非常重要！)
    # 字体文件放进去了，但 Wine 不一定会立刻重修构建 fntdata.dat
    # 杀死 wineserver 会强制 Wine 下次启动时重新扫描系统和本地配置
    log "Refreshing Wine font cache..."
    if command -v wineserver &> /dev/null; then
        # 必须以目标用户身份执行 wineserver -k
        as_user env WINEPREFIX="$WINE_PREFIX" wineserver -k
    fi
    
    success "Wine fonts installed and cache refresh triggered."
  else
    warn "Resources font directory not found at: $FONT_SRC"
  fi
fi

if command -v lutris &> /dev/null; then 
    log "Lutris detected. Installing 32-bit gaming dependencies..."
    pacman -S --noconfirm --needed alsa-plugins giflib glfw gst-plugins-base-libs lib32-alsa-plugins lib32-giflib lib32-gst-plugins-base-libs lib32-gtk3 lib32-libjpeg-turbo lib32-libva lib32-mpg123  lib32-openal libjpeg-turbo libva libxslt mpg123 openal ttf-liberation
fi
# --- Steam Locale Fix ---
STEAM_desktop_modified=false
NATIVE_DESKTOP="/usr/share/applications/steam.desktop"
if [ -f "$NATIVE_DESKTOP" ]; then
    log "Checking Native Steam..."
    if ! grep -q "env LANG=zh_CN.UTF-8" "$NATIVE_DESKTOP"; then
        exe sed -i 's|^Exec=/usr/bin/steam|Exec=env LANG=zh_CN.UTF-8 /usr/bin/steam|' "$NATIVE_DESKTOP"
        exe sed -i 's|^Exec=steam|Exec=env LANG=zh_CN.UTF-8 steam|' "$NATIVE_DESKTOP"
        success "Patched Native Steam .desktop."
        STEAM_desktop_modified=true
    else
        log "Native Steam already patched."
    fi
fi

if flatpak list | grep -q "com.valvesoftware.Steam"; then
    log "Checking Flatpak Steam..."
    exe flatpak override --env=LANG=zh_CN.UTF-8 com.valvesoftware.Steam
    success "Applied Flatpak Steam override."
    STEAM_desktop_modified=true
fi

# --- [MOVED] LazyVim Configuration ---
if [ "$INSTALL_LAZYVIM" = true ]; then
  section "Config" "Applying LazyVim Overrides"
  NVIM_CFG="$HOME_DIR/.config/nvim"

  if [ -d "$NVIM_CFG" ]; then
    BACKUP_PATH="$HOME_DIR/.config/nvim.old.apps.$(date +%s)"
    warn "Collision detected. Moving existing nvim config to $BACKUP_PATH"
    mv "$NVIM_CFG" "$BACKUP_PATH"
  fi

  log "Cloning LazyVim starter..."
  if as_user git clone https://github.com/LazyVim/starter "$NVIM_CFG"; then
    rm -rf "$NVIM_CFG/.git"
    success "LazyVim installed (Override)."
  else
    error "Failed to clone LazyVim."
  fi
fi

# --- hide desktop ---
hide_desktop_file() {

  local file="$1"

  if [[ -f "$file" ]] && ! grep -q "^NoDisplay=true$" "$file"; then

    echo "NoDisplay=true" >> "$file"

  fi

}
section "Config" "Hiding useless .desktop files"
log "Hiding useless .desktop files"
hide_desktop_file "/usr/share/applications/avahi-discover.desktop"
hide_desktop_file "/usr/share/applications/qv4l2.desktop"
hide_desktop_file "/usr/share/applications/qvidcap.desktop"
hide_desktop_file "/usr/share/applications/bssh.desktop"
hide_desktop_file "/usr/share/applications/org.fcitx.Fcitx5.desktop"
hide_desktop_file "/usr/share/applications/org.fcitx.fcitx5-migrator.desktop"
hide_desktop_file "/usr/share/applications/xgps.desktop"
hide_desktop_file "/usr/share/applications/xgpsspeed.desktop"
hide_desktop_file "/usr/share/applications/gvim.desktop"
hide_desktop_file "/usr/share/applications/kbd-layout-viewer5.desktop"
hide_desktop_file "/usr/share/applications/bvnc.desktop"
hide_desktop_file "/usr/share/applications/yazi.desktop"
hide_desktop_file "/usr/share/applications/btop.desktop"
hide_desktop_file "/usr/share/applications/vim.desktop"
hide_desktop_file "/usr/share/applications/nvim.desktop"
hide_desktop_file "/usr/share/applications/nvtop.desktop"
hide_desktop_file "/usr/share/applications/mpv.desktop"
hide_desktop_file "/usr/share/applications/org.gnome.Settings.desktop"

# --- Post-Dotfiles Configuration: Firefox ---
# Define resource path (shorin-arch-setup/resources/firefox/user.js.snippet)
FF_SNIPPET="$PARENT_DIR/resources/firefox/user.js.snippet"

# # ---- firefox customization-----
# # command -v firefox 会检查 firefox 可执行文件是否存在于 PATH 中
# if command -v firefox &>/dev/null; then

#     if [ -f "$FF_SNIPPET" ]; then
#         section "Config" "Firefox UI Customization"
        
#         log "Initializing Firefox Profile..."
#         # 1. 启动 Headless Firefox 以生成配置文件夹 (User Mode)
#         as_user env LANG=zh_CN.UTF-8 firefox --headless >/dev/null 2>&1 &
#         sleep 3
#         # 确保进程已完全终止
#         pkill firefox
#         sleep 3

#         # 寻找生成的 Profile 目录
#         PROFILE_DIR=$(find "$HOME_DIR/.mozilla/firefox" -maxdepth 1 -type d -name "*.default-release" 2>/dev/null | head -n 1)
        
#         if [ -n "$PROFILE_DIR" ]; then
#             USER_JS="$PROFILE_DIR/user.js"
#             log "Found Profile: $(basename "$PROFILE_DIR")"
            
#             # 2. 备份现有的 user.js (如果存在)
#             HAS_EXISTING_USER_JS=false
#             if [ -f "$USER_JS" ]; then
#                  as_user cp "$USER_JS" "$USER_JS.bak"
#                  HAS_EXISTING_USER_JS=true
#             fi

#             log "Injecting UI settings..."
#             # 3. 注入配置片段和自定义设置
#             as_user bash -c "cat '$FF_SNIPPET' >> '$USER_JS'"
            
#             # 注入垂直标签页等特定设置
#             as_user bash -c "echo 'user_pref(\"sidebar.verticalTabs\", true);' >> '$USER_JS'"
#             as_user bash -c "echo 'user_pref(\"sidebar.visibility\", \"expand-on-hover\");' >> '$USER_JS'"
#             as_user bash -c "echo 'user_pref(\"browser.toolbars.bookmarks.visibility\", \"never\");' >> '$USER_JS'"
#             as_user bash -c "echo 'user_pref(\"browser.sessionstore.resume_from_crash\", false);' >> '$USER_JS'"
#             log "Applying settings (Headless Startup)..."
#             # 4. 再次启动 Headless Firefox 以应用配置
#             as_user env LANG=zh_CN.UTF-8 firefox --headless >/dev/null 2>&1 &
#             log "Waiting for initialization (5s)..."
#             sleep 5
#             log "Closing Firefox..."
#             # 杀掉目标用户的 firefox 进程，确保配置写入 prefs.js
#             pkill firefox
#             sleep 3

#             log "fix firefox maximize issue"
#             XUL_STORE="$PROFILE_DIR/xulStore.json"
# cat <<EOF > "$XUL_STORE"
# {
#     "chrome://browser/content/browser.xhtml": {
#         "main-window": {
#             "sizemode": "normal"
#         }
#     }
# }
# EOF
#             chown -R "$TARGET_USER" "$XUL_STORE"
#             log "Cleaning up injection..."
#             # 5. 清理/还原 user.js
#             if [ "$HAS_EXISTING_USER_JS" = true ]; then
#                  as_user mv "$USER_JS.bak" "$USER_JS"
#                  log "Restored original user.js"
#             else
#                  as_user rm "$USER_JS"
#                  log "Removed temporary user.js"
#             fi
            
#             success "Firefox configured."
#         else
#             warn "Firefox profile not found. Skipping customization."
#         fi
#     else
#         # 如果找不到 snippet 文件，仅打印警告但不中断脚本
#         if [ -d "$PARENT_DIR/resources/firefox" ]; then
#              warn "user.js.snippet not found in resources/firefox."
#         fi
#     fi

# else
#     log "Skipping Firefox config (Not installed)"
# fi
mkdir -p $HOME_DIR/.mozilla
cp -rf $PARENT_DIR/resources/firefox $HOME_DIR/.mozilla/.
chown -R $TARGET_USER $HOME_DIR/.mozilla
# ------------------------------------------------------------------------------
# [FIX] CLEANUP GLOBAL SUDO CONFIGURATION
# ------------------------------------------------------------------------------
if [ -f "$SUDO_TEMP_FILE" ]; then
    log "Revoking temporary NOPASSWD..."
    rm -f "$SUDO_TEMP_FILE"
fi

# ------------------------------------------------------------------------------
# 5. Generate Failure Report
# ------------------------------------------------------------------------------
if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
    DOCS_DIR="$HOME_DIR/Documents"
    REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"
    
    if [ ! -d "$DOCS_DIR" ]; then as_user mkdir -p "$DOCS_DIR"; fi
    
    echo -e "\n========================================================" >> "$REPORT_FILE"
    echo -e " Installation Failure Report - $(date)" >> "$REPORT_FILE"
    echo -e "========================================================" >> "$REPORT_FILE"
    printf "%s\n" "${FAILED_PACKAGES[@]}" >> "$REPORT_FILE"
    
    chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
    
    echo ""
    warn "Some applications failed to install."
    warn "A report has been saved to:"
    echo -e "   ${BOLD}$REPORT_FILE${NC}"
else
    success "All scheduled applications processed successfully."
fi

# Reset Trap
trap - INT

log "Module 99-apps completed."