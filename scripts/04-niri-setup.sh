#!/bin/bash

# ==============================================================================
# 04-niri-setup.sh - Niri Desktop (Restored FZF & Robust AUR)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}
UNDO_SCRIPT="$SCRIPT_DIR/niri-undochange.sh"

# --- [CONFIGURATION] ---
# LazyVim 硬性依赖列表
LAZYVIM_DEPS=("neovim" "ripgrep" "fd" "ttf-jetbrains-mono-nerd" "git")

check_root

# --- [HELPER FUNCTIONS] ---

# 1. 简化的用户执行封装
as_user() {
  runuser -u "$TARGET_USER" -- "$@"
}

# 2. Critical Failure Handler (The "Big Red Box")
critical_failure_handler() {
  local failed_reason="$1"
  trap - ERR

  echo ""
  echo -e "\033[0;31m################################################################\033[0m"
  echo -e "\033[0;31m#                                                              #\033[0m"
  echo -e "\033[0;31m#   CRITICAL INSTALLATION FAILURE DETECTED                     #\033[0m"
  echo -e "\033[0;31m#                                                              #\033[0m"
  echo -e "\033[0;31m#   Reason: $failed_reason\033[0m"
  echo -e "\033[0;31m#                                                              #\033[0m"
  echo -e "\033[0;31m#   OPTIONS(Choose one):                                       #\033[0m"
  echo -e "\033[0;31m#   1. Restore snapshot                                        #\033[0m"
  echo -e "\033[0;31m#   2. Fix manually and re-run: sudo bash install.sh           #\033[0m"
  echo -e "\033[0;31m#                                                              #\033[0m"
  echo -e "\033[0;31m################################################################\033[0m"
  echo ""

  while true; do
    read -p "Execute System Recovery (Restore Snapshot)? [y/n]: " -r choice
    case "$choice" in
    [yY]*)
      if [ -f "$UNDO_SCRIPT" ]; then
        warn "Executing recovery script..."
        bash "$UNDO_SCRIPT"
        exit 1
      else
        error "Recovery script missing! You are on your own."
        exit 1
      fi
      ;;
    [nN]*)
      warn "User chose NOT to recover."
      warn "Please fix the issue manually before re-running."
      error "Installation aborted."
      exit 1
      ;;
    *) echo "Invalid input. Please enter 'y' or 'n'." ;;
    esac
  done
}

# 3. Robust Package Installation with Retry Loop
ensure_package_installed() {
  local pkg="$1"
  local context="$2" # e.g., "Repo" or "AUR"
  local max_attempts=3
  local attempt=1
  local install_success=false

  # 1. Check if already installed
  if pacman -Q "$pkg" &>/dev/null; then
    return 0
  fi

  # 2. Retry Loop
  while [ $attempt -le $max_attempts ]; do
    if [ $attempt -gt 1 ]; then
      warn "Retrying '$pkg' ($context)... (Attempt $attempt/$max_attempts)"
      sleep 3 # Cooldown
    else
      log "Installing '$pkg' ($context)..."
    fi

    # Try installation
    if as_user yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "$pkg"; then
      install_success=true
      break
    else
      warn "Attempt $attempt/$max_attempts failed for '$pkg'."
    fi

    ((attempt++))
  done

  # 3. Final Verification
  if [ "$install_success" = true ] && pacman -Q "$pkg" &>/dev/null; then
    success "Installed '$pkg'."
  else
    critical_failure_handler "Failed to install '$pkg' after $max_attempts attempts."
  fi
}

# hide .desktop
hide_desktop_file() {

  local file="$1"

  if [[ -f "$file" ]] && ! grep -q "^NoDisplay=true$" "$file"; then

    echo "NoDisplay=true" >> "$file"

  fi

}


# Ensure whiptail
if ! command -v whiptail &>/dev/null; then
  log "Installing dependency: whiptail..."
  pacman -S --noconfirm libnewt >/dev/null 2>&1
fi

section "Phase 4" "Niri Desktop Environment"

# ==============================================================================
# STEP 0: Safety Checkpoint
# ==============================================================================

create_checkpoint() {
  local marker="Before Niri Setup"
  if snapper -c root list | grep -q "$marker"; then
    log "Checkpoint '$marker' already exists."
  else
    log "Creating safety checkpoint..."
    snapper -c root create -d "$marker"
    snapper -c home list &>/dev/null && snapper -c home create -d "$marker"
    success "Checkpoint created."
  fi
}
create_checkpoint

# Enable Trap
trap 'critical_failure_handler "Script Error at Line $LINENO"' ERR

# ==============================================================================
# STEP 1: Identify User & DM Check
# ==============================================================================
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# DM Check
KNOWN_DMS=("gdm" "sddm" "lightdm" "lxdm" "slim" "xorg-xdm" "ly" "greetd")
SKIP_AUTOLOGIN=false
DM_FOUND=""
for dm in "${KNOWN_DMS[@]}"; do
  if pacman -Q "$dm" &>/dev/null; then
    DM_FOUND="$dm"
    break
  fi
done

if [ -n "$DM_FOUND" ]; then
  info_kv "Conflict" "${H_RED}$DM_FOUND${NC}"
  SKIP_AUTOLOGIN=true
else
  read -t 20 -p "$(echo -e "   ${H_CYAN}Enable TTY auto-login? [Y/n] (Default Y): ${NC}")" choice || true
  [[ "${choice:-Y}" =~ ^[Yy]$ ]] && SKIP_AUTOLOGIN=false || SKIP_AUTOLOGIN=true
fi

# ==============================================================================
# STEP 2: Core Components
# ==============================================================================
section "Step 1/9" "Core Components"
PKGS="niri xdg-desktop-portal-gnome fuzzel kitty firefox libnotify mako polkit-gnome"
exe pacman -Syu --noconfirm --needed $PKGS

log "Configuring Firefox Policies..."
POL_DIR="/etc/firefox/policies"
exe mkdir -p "$POL_DIR"
echo '{ "policies": { "Extensions": { "Install": ["https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"] } } }' >"$POL_DIR/policies.json"
exe chmod 755 "$POL_DIR" && exe chmod 644 "$POL_DIR/policies.json"

# ==============================================================================
# STEP 3: File Manager
# ==============================================================================
section "Step 2/9" "File Manager"
exe pacman -S --noconfirm --needed ffmpegthumbnailer gvfs-smb nautilus-open-any-terminal file-roller gnome-keyring gst-plugins-base gst-plugins-good gst-libav nautilus

if [ ! -f /usr/bin/gnome-terminal ] || [ -L /usr/bin/gnome-terminal ]; then
  exe ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
fi

# Nautilus Nvidia/Input Fix
DESKTOP_FILE="/usr/share/applications/org.gnome.Nautilus.desktop"
if [ -f "$DESKTOP_FILE" ]; then
  GPU_COUNT=$(lspci | grep -E -i "vga|3d" | wc -l)
  HAS_NVIDIA=$(lspci | grep -E -i "nvidia" | wc -l)
  ENV_VARS="env GTK_IM_MODULE=fcitx"
  [ "$GPU_COUNT" -gt 1 ] && [ "$HAS_NVIDIA" -gt 0 ] && ENV_VARS="env GSK_RENDERER=gl GTK_IM_MODULE=fcitx"

  if ! grep -q "^Exec=$ENV_VARS" "$DESKTOP_FILE"; then
    exe sed -i "s|^Exec=|Exec=$ENV_VARS |" "$DESKTOP_FILE"
  fi
fi

# ==============================================================================
# STEP 4: Network Optimization
# ==============================================================================
section "Step 3/9" "Network Optimization"
exe pacman -S --noconfirm --needed flatpak gnome-software
exe flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

CURRENT_TZ=$(readlink -f /etc/localtime)
IS_CN_ENV=false
if [[ "$CURRENT_TZ" == *"Shanghai"* ]] || [ "$CN_MIRROR" == "1" ] || [ "$DEBUG" == "1" ]; then
  IS_CN_ENV=true
  info_kv "Region" "China Optimization Active"
fi

if [ "$IS_CN_ENV" = true ]; then
  select_flathub_mirror
else
  log "Using Global Sources."
fi

SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

# ==============================================================================
# STEP 5: Dependencies (RESTORED FZF)
# ==============================================================================
section "Step 4/9" "Dependencies"
LIST_FILE="$PARENT_DIR/niri-applist.txt"

# Ensure tools
command -v fzf &>/dev/null || pacman -S --noconfirm fzf >/dev/null 2>&1

if [ -f "$LIST_FILE" ]; then
  mapfile -t DEFAULT_LIST < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | sed 's/#.*//; s/AUR://g' | xargs -n1)

  if [ ${#DEFAULT_LIST[@]} -eq 0 ]; then
    warn "App list is empty. Skipping."
    PACKAGE_ARRAY=()
  else
    echo -e "\n   ${H_YELLOW}>>> Default installation in 60s. Press ANY KEY to customize...${NC}"

    if read -t 60 -n 1 -s -r; then
      # --- [RESTORED] Original FZF Selection Logic ---
      clear
      log "Loading package list..."

      SELECTED_LINES=$(grep -vE "^\s*#|^\s*$" "$LIST_FILE" |
        sed -E 's/[[:space:]]+#/\t#/' |
        fzf --multi \
          --layout=reverse \
          --border \
          --margin=1,2 \
          --prompt="Search Pkg > " \
          --pointer=">>" \
          --marker="* " \
          --delimiter=$'\t' \
          --with-nth=1 \
          --bind 'load:select-all' \
          --bind 'ctrl-a:select-all,ctrl-d:deselect-all' \
          --info=inline \
          --header="[TAB] TOGGLE | [ENTER] INSTALL | [CTRL-D] DE-ALL | [CTRL-A] SE-ALL" \
          --preview "echo {} | cut -f2 -d$'\t' | sed 's/^# //'" \
          --preview-window=right:50%:wrap:border-left \
          --color=dark \
          --color=fg+:white,bg+:black \
          --color=hl:blue,hl+:blue:bold \
          --color=header:yellow:bold \
          --color=info:magenta \
          --color=prompt:cyan,pointer:cyan:bold,marker:green:bold \
          --color=spinner:yellow)

      clear

      if [ -z "$SELECTED_LINES" ]; then
        warn "User cancelled selection. Installing NOTHING."
        PACKAGE_ARRAY=()
      else
        PACKAGE_ARRAY=()
        while IFS= read -r line; do
          raw_pkg=$(echo "$line" | cut -f1 -d$'\t' | xargs)
          clean_pkg="${raw_pkg#AUR:}"
          [ -n "$clean_pkg" ] && PACKAGE_ARRAY+=("$clean_pkg")
        done <<<"$SELECTED_LINES"
      fi
      # -----------------------------------------------
    else
      log "Auto-confirming ALL packages."
      PACKAGE_ARRAY=("${DEFAULT_LIST[@]}")
    fi
  fi

  # --- Pre-Installation Filter (LazyVim Interceptor) ---
  INSTALL_LAZYVIM=false
  FINAL_ARRAY=()
  if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
    for pkg in "${PACKAGE_ARRAY[@]}"; do
      if [ "${pkg,,}" == "lazyvim" ]; then
        INSTALL_LAZYVIM=true
        FINAL_ARRAY+=("${LAZYVIM_DEPS[@]}")
        info_kv "Config" "LazyVim detected" "Setup deferred to post-dotfiles"
      else
        FINAL_ARRAY+=("$pkg")
      fi
    done
    PACKAGE_ARRAY=("${FINAL_ARRAY[@]}")
  fi

  # --- Installation Loop ---
  if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
    BATCH_LIST=()
    AUR_LIST=()
    info_kv "Target" "${#PACKAGE_ARRAY[@]} packages scheduled."

    for pkg in "${PACKAGE_ARRAY[@]}"; do
      [ "$pkg" == "imagemagic" ] && pkg="imagemagick"
      [[ "$pkg" == "AUR:"* ]] && AUR_LIST+=("${pkg#AUR:}") || BATCH_LIST+=("$pkg")
    done

    # 1. Batch Install Repo Packages
    if [ ${#BATCH_LIST[@]} -gt 0 ]; then
      log "Phase 1: Batch Installing Repo Packages..."
      as_user yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "${BATCH_LIST[@]}" || true

      # Verify Each
      for pkg in "${BATCH_LIST[@]}"; do
        ensure_package_installed "$pkg" "Repo"
      done
    fi

    # 2. Sequential AUR Install
    if [ ${#AUR_LIST[@]} -gt 0 ]; then
      log "Phase 2: Installing AUR Packages (Sequential)..."
      for pkg in "${AUR_LIST[@]}"; do
        ensure_package_installed "$pkg" "AUR"
      done
    fi

    # Waybar fallback
    if ! command -v waybar &>/dev/null; then
      warn "Waybar missing. Installing stock..."
      exe pacman -S --noconfirm --needed waybar
    fi
  else
    warn "No packages selected."
  fi
else
  warn "niri-applist.txt not found."
fi

# ==============================================================================
# STEP 6: Dotfiles & LazyVim
# ==============================================================================
section "Step 5/9" "Deploying Dotfiles"

REPO_GITHUB="https://github.com/SHORiN-KiWATA/ShorinArchExperience-ArchlinuxGuide.git"
REPO_GITEE="https://gitee.com/shorinkiwata/ShorinArchExperience-ArchlinuxGuide.git"
TEMP_DIR="/tmp/shorin-repo"
rm -rf "$TEMP_DIR"

log "Cloning configuration..."
if ! as_user git clone "$REPO_GITHUB" "$TEMP_DIR"; then
  warn "GitHub failed. Trying Gitee..."
  rm -rf "$TEMP_DIR"
  if ! as_user git clone "$REPO_GITEE" "$TEMP_DIR"; then
    critical_failure_handler "Failed to clone dotfiles from any source."
  fi
fi

if [ -d "$TEMP_DIR/dotfiles" ]; then
  # Filter Exclusions
  if [ "$TARGET_USER" != "shorin" ]; then
    EXCLUDE_FILE="$PARENT_DIR/exclude-dotfiles.txt"
    if [ -f "$EXCLUDE_FILE" ]; then
      log "Processing exclusions..."
      while IFS= read -r item; do
        item=$(echo "$item" | tr -d '\r' | xargs)
        [ -n "$item" ] && [[ ! "$item" =~ ^# ]] && rm -rf "$TEMP_DIR/dotfiles/.config/$item"
      done <"$EXCLUDE_FILE"
    fi
  fi

  # Backup & Apply
  log "Backing up & Applying..."
  as_user tar -czf "$HOME_DIR/config_backup_$(date +%s).tar.gz" -C "$HOME_DIR" .config
  as_user cp -rf "$TEMP_DIR/dotfiles/." "$HOME_DIR/"

# Post-Process
  if [ "$TARGET_USER" != "shorin" ]; then
    as_user truncate -s 0 "$HOME_DIR/.config/niri/output.kdl" 2>/dev/null
    
    # 定义书签文件路径
    BOOKMARKS_FILE="$HOME_DIR/.config/gtk-3.0/bookmarks"
    
    # 如果文件存在，则执行替换操作
    if [ -f "$BOOKMARKS_FILE" ]; then
        # 使用 sed 将文件中的 "shorin" 全部替换为当前目标用户名
        # 使用 as_user 确保文件权限不会变成 root
        as_user sed -i "s/shorin/$TARGET_USER/g" "$BOOKMARKS_FILE"
        log "Updated GTK bookmarks path from 'shorin' to '$TARGET_USER'."
    fi
    # --- 修改结束 ---
  fi

  # Fix Symlinks & Permissions
  GTK4="$HOME_DIR/.config/gtk-4.0"
  THEME="$HOME_DIR/.themes/adw-gtk3-dark/gtk-4.0"
  as_user rm -f "$GTK4/gtk.css" "$GTK4/gtk-dark.css"
  as_user ln -sf "$THEME/gtk-dark.css" "$GTK4/gtk-dark.css"
  as_user ln -sf "$THEME/gtk.css" "$GTK4/gtk.css"

  if command -v flatpak &>/dev/null; then
    as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
    as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
    as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    as_user flatpak override --user --filesystem=xdg-config/fontconfig
  fi
  success "Dotfiles Applied."
else
  warn "Dotfiles missing in temp directory."
fi

# --- Post-Dotfiles Configuration: LazyVim ---
if [ "$INSTALL_LAZYVIM" = true ]; then
  section "Config" "Applying LazyVim Overrides"
  NVIM_CFG="$HOME_DIR/.config/nvim"

  if [ -d "$NVIM_CFG" ]; then
    BACKUP_PATH="$HOME_DIR/.config/nvim.old.dotfiles.$(date +%s)"
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
# --- Post-Dotfiles Configuration: Firefox ---
# Define resource path (shorin-arch-setup/resources/firefox/user.js.snippet)
FF_SNIPPET="$PARENT_DIR/resources/firefox/user.js.snippet"

# 【新增】检查 Firefox 是否已安装
# command -v firefox 会检查 firefox 可执行文件是否存在于 PATH 中
if command -v firefox &>/dev/null; then

    if [ -f "$FF_SNIPPET" ]; then
        section "Config" "Firefox UI Customization"
        
        log "Initializing Firefox Profile..."
        # 1. 启动 Headless Firefox 以生成配置文件夹 (User Mode)
        # 使用 timeout 防止进程卡死，确保它运行足够长时间以生成文件
        as_user firefox --headless >/dev/null 2>&1 || true
        sleep 3
        # 确保进程已完全终止
        pkill firefox >/dev/null
        sleep 3

        # 寻找生成的 Profile 目录
        PROFILE_DIR=$(find "$HOME_DIR/.mozilla/firefox" -maxdepth 1 -type d -name "*.default-release" 2>/dev/null | head -n 1)
        
        if [ -n "$PROFILE_DIR" ]; then
            USER_JS="$PROFILE_DIR/user.js"
            log "Found Profile: $(basename "$PROFILE_DIR")"
            
            # 2. 备份现有的 user.js (如果存在)
            HAS_EXISTING_USER_JS=false
            if [ -f "$USER_JS" ]; then
                 as_user cp "$USER_JS" "$USER_JS.bak"
                 HAS_EXISTING_USER_JS=true
            fi

            log "Injecting UI settings..."
            # 3. 注入配置片段和自定义设置
            # 使用 bash -c 确保重定向操作符 >> 是以普通用户权限执行的
            as_user bash -c "cat '$FF_SNIPPET' >> '$USER_JS'"
            
            # 注入垂直标签页等特定设置
            as_user bash -c "echo 'user_pref(\"sidebar.verticalTabs\", true);' >> '$USER_JS'"
            as_user bash -c "echo 'user_pref(\"sidebar.visibility\", \"expand-on-hover\");' >> '$USER_JS'"
            as_user bash -c "echo 'user_pref(\"browser.toolbars.bookmarks.visibility\", \"never\");' >> '$USER_JS'"
            
            log "Applying settings (Headless Startup)..."
            # 4. 再次启动 Headless Firefox 以应用配置
            as_user firefox --headless >/dev/null 2>&1 &
            FF_PID=$!
            
            log "Waiting for initialization (5s)..."
            sleep 5
            
            log "Closing Firefox..."
            # 杀掉目标用户的 firefox 进程，确保配置写入 prefs.js
            pkill firefox
            wait 2>/dev/null
            
            log "Cleaning up injection..."
            # 5. 清理/还原 user.js
            if [ "$HAS_EXISTING_USER_JS" = true ]; then
                 as_user mv "$USER_JS.bak" "$USER_JS"
                 log "Restored original user.js"
            else
                 as_user rm "$USER_JS"
                 log "Removed temporary user.js"
            fi
            
            success "Firefox configured."
        else
            warn "Firefox profile not found. Skipping customization."
        fi
    else
        # 如果找不到 snippet 文件，仅打印警告但不中断脚本
        if [ -d "$PARENT_DIR/resources/firefox" ]; then
             warn "user.js.snippet not found in resources/firefox."
        fi
    fi

else
    log "Skipping Firefox config (Not installed)"
fi

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
# ==============================================================================
# STEP 7: Wallpapers & Templates
# ==============================================================================
section "Step 6/9" "Wallpapers"
if [ -d "$TEMP_DIR/wallpapers" ]; then
  as_user mkdir -p "$HOME_DIR/Pictures/Wallpapers"
  as_user cp -rf "$TEMP_DIR/wallpapers/." "$HOME_DIR/Pictures/Wallpapers/"
  as_user touch "$HOME_DIR/Templates/new"
  as_user touch "$HOME_DIR/Templates/new.sh"
  as_user echo "#!/bin/bash" >> "$HOME_DIR/Templates/new.sh"
  success "Installed."
fi
rm -rf "$TEMP_DIR"

# ==============================================================================
# STEP 8: Hardware Tools
# ==============================================================================
section "Step 7/9" "Hardware"
if pacman -Q ddcutil &>/dev/null; then
  gpasswd -a "$TARGET_USER" i2c
  lsmod | grep -q i2c_dev || echo "i2c-dev" >/etc/modules-load.d/i2c-dev.conf
fi
if pacman -Q swayosd &>/dev/null; then
  systemctl enable --now swayosd-libinput-backend.service >/dev/null 2>&1
fi
success "Tools configured."

# ==============================================================================
# STEP 9: Cleanup & Auto-Login
# ==============================================================================
section "Final" "Cleanup & Boot"
rm -f "$SUDO_TEMP_FILE"

SVC_DIR="$HOME_DIR/.config/systemd/user"
SVC_FILE="$SVC_DIR/niri-autostart.service"
LINK="$SVC_DIR/default.target.wants/niri-autostart.service"

if [ "$SKIP_AUTOLOGIN" = true ]; then
  log "Auto-login skipped."
  as_user rm -f "$LINK" "$SVC_FILE"
else
  log "Configuring TTY Auto-login..."
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
  success "Enabled."
fi

trap - ERR
log "Module 04 completed."
