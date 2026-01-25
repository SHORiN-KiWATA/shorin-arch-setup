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

check_root

# --- [HELPER FUNCTIONS] ---


# 2. Critical Failure Handler (The "Big Red Box")
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
  echo -e "\033[0;31m#   OPTIONS:                                                   #\033[0m"
  echo -e "\033[0;31m#   1. Restore snapshot (Undo changes & Exit)                  #\033[0m"
  echo -e "\033[0;31m#   2. Retry / Re-run script                                   #\033[0m"
  echo -e "\033[0;31m#   3. Abort (Exit immediately)                                #\033[0m"
  echo -e "\033[0;31m#                                                              #\033[0m"
  echo -e "\033[0;31m################################################################\033[0m"
  echo ""

  while true; do
    read -p "Select an option [1-3]: " -r choice
    case "$choice" in
    1)
      # Option 1: Restore Snapshot
      if [ -f "$UNDO_SCRIPT" ]; then
        warn "Executing recovery script..."
        bash "$UNDO_SCRIPT"
        exit 1
      else
        error "Recovery script missing! You are on your own."
        exit 1
      fi
      ;;
    2)
      # Option 2: Re-run Script
      warn "Restarting installation script..."
      echo "-----------------------------------------------------"
      sleep 1
      exec "$0" "$@"
      ;;
    3)
      # Option 3: Exit
      warn "User chose to abort."
      warn "Please fix the issue manually before re-running."
      error "Installation aborted."
      exit 1
      ;;
    *) 
      echo "Invalid input. Please enter 1, 2, or 3." 
      ;;
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
    if as_user yay -S --noconfirm --needed --answerdiff=None --answerclean=None "$pkg"; then
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

section "Phase 4" "Niri Desktop Environment"

# ==============================================================================
# STEP 0: Safety Checkpoint
# ==============================================================================

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
exe pacman -S --noconfirm --needed $PKGS

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

exe pacman -S --noconfirm --needed xdg-desktop-portal-gtk thunar tumbler ffmpegthumbnailer poppler-glib gvfs-smb file-roller thunar-archive-plugin gnome-keyring thunar-volman gvfs-mtp gvfs-gphoto2 webp-pixbuf-loader libgsf

if [ ! -f /usr/bin/gnome-terminal ] || [ -L /usr/bin/gnome-terminal ]; then
  exe ln -sf /usr/bin/kitty /usr/bin/gnome-terminal
fi

# Nautilus Nvidia/Input Fix
configure_nautilus_user

section "Step 3/9" "Temp sudo file"

SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Temp sudo file created..."
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
# STEP 6: Dotfiles (Smart Recursive Symlink)
# ==============================================================================
section "Step 5/9" "Deploying Dotfiles"

REPO_GITHUB="https://github.com/SHORiN-KiWATA/ShorinArchExperience-ArchlinuxGuide.git"

# 1. 仓库位置：放在 .local/share 下，不污染 home 根目录
DOTFILES_REPO="$HOME_DIR/.local/share/shorin-niri"

# --- Smart Linking Function ---
# 核心逻辑：只链接“叶子”节点，对于“容器”目录（.config, .local, share）则递归进入
link_recursive() {
  local src_dir="$1"
  local dest_dir="$2"
  local exclude_list="$3"

  # 确保目标容器目录存在 (比如确保 ~/.local/share 存在)
  as_user mkdir -p "$dest_dir"

  find "$src_dir" -mindepth 1 -maxdepth 1 -not -path '*/.git*' | while read -r src_path; do
    local item_name
    item_name=$(basename "$src_path")

    # 0. 排除检查
    if echo "$exclude_list" | grep -qw "$item_name"; then
      log "Skipping excluded: $item_name"
      continue
    fi

    # 1. 判断是否是需要“穿透”的系统目录
    # 规则：如果遇到 .config, .local，或者 .local 下面的 share/bin，不要链接，而是递归
    local need_recurse=false

    if [ "$item_name" == ".config" ]; then
        need_recurse=true
    elif [ "$item_name" == ".local" ]; then
        need_recurse=true
    # 只有当父目录名字是以 .local 结尾时，才穿透 share 和 bin
    elif [[ "$src_dir" == *".local" ]] && { [ "$item_name" == "share" ] || [ "$item_name" == "bin" ]; }; then
        need_recurse=true
    fi

    if [ "$need_recurse" = true ]; then
        # 递归进入：传入当前路径作为新的源和目标
        link_recursive "$src_path" "$dest_dir/$item_name" "$exclude_list"
    else
        # 2. 具体的配置文件夹/文件（如 fcitx5, niri, .zshrc） -> 执行链接
        local target_path="$dest_dir/$item_name"
        
        # 先清理旧的目标（无论是文件、文件夹还是死链）
        if [ -e "$target_path" ] || [ -L "$target_path" ]; then
            as_user rm -rf "$target_path"
        fi
        
        # 创建软链接
        # 效果：~/.local/share/fcitx5 -> ~/.local/share/shorin-niri/dotfiles/.local/share/fcitx5
        as_user ln -sf "$src_path" "$target_path"
    fi
  done
}

# --- Execution ---

# 1. 准备仓库
prepare_repository() {
  local TARGET_DIRS=("dotfiles" "wallpapers")
  # 建议定义一个变量指定主分支名，防止以后 Github 变成 other-branch
  local BRANCH_NAME="main" 

  if [ ! -d "$DOTFILES_REPO" ]; then
    log "Initializing Sparse & Shallow Checkout to $DOTFILES_REPO..."
    as_user mkdir -p "$DOTFILES_REPO"
    
    as_user git -C "$DOTFILES_REPO" init
    # 强制将本地分支名设为 main，避免本地是 master 远程是 main 造成的混乱
    as_user git -C "$DOTFILES_REPO" branch -m "$BRANCH_NAME"
    
    as_user git -C "$DOTFILES_REPO" config core.sparseCheckout true
    local sparse_file="$DOTFILES_REPO/.git/info/sparse-checkout"
    for item in "${TARGET_DIRS[@]}"; do
      echo "$item" | as_user tee -a "$sparse_file" >/dev/null
    done
    
    as_user git -C "$DOTFILES_REPO" remote add origin "$REPO_GITHUB"
    
    log "Downloading latest snapshot (Github)..."
    # 修复点 2：同样明确指定 origin main
    if ! as_user git -C "$DOTFILES_REPO" pull origin "$BRANCH_NAME" --depth 1; then # <--- 修改
      critical_failure_handler "Failed to download dotfiles (Sparse+Shallow failed)."
    else 
      as_user git -C "$DOTFILES_REPO" branch --set-upstream-to=origin/main main
      as_user git config --global --add safe.directory "$DOTFILES_REPO"
    fi

  fi
}

prepare_repository

# 2. 执行链接
if [ -d "$DOTFILES_REPO/dotfiles" ]; then
  EXCLUDE_LIST=""
  if [ "$TARGET_USER" != "shorin" ]; then
    EXCLUDE_FILE="$PARENT_DIR/exclude-dotfiles.txt"
    if [ -f "$EXCLUDE_FILE" ]; then
      log "Loading exclusions..."
      EXCLUDE_LIST=$(grep -vE "^\s*#|^\s*$" "$EXCLUDE_FILE" | tr '\n' ' ')
    fi
  fi

  log "Backing up existing configs..."
  as_user tar -czf "$HOME_DIR/config_backup_$(date +%s).tar.gz" -C "$HOME_DIR" .config

  # 调用递归函数：从 dotfiles 根目录开始，目标是 HOME
  link_recursive "$DOTFILES_REPO/dotfiles" "$HOME_DIR" "$EXCLUDE_LIST"

  # --- Post-Process (防止污染 git 的修正) ---
  OUTPUT_EXAMPLE_KDL="$HOME_DIR/.config/niri/output-example.kdl"
  OUTPUT_KDL="$HOME_DIR/.config/niri/output.kdl"
  if [ "$TARGET_USER" != "shorin" ]; then

    as_user touch $OUTPUT_KDL

    # 修复 Bookmarks (转为实体文件并修改)
    BOOKMARKS_FILE="$HOME_DIR/.config/gtk-3.0/bookmarks"
    REPO_BOOKMARKS="$DOTFILES_REPO/dotfiles/.config/gtk-3.0/bookmarks"
    if [ -f "$REPO_BOOKMARKS" ]; then
        as_user sed -i "s/shorin/$TARGET_USER/g" "$REPO_BOOKMARKS"
        log "Updated GTK bookmarks."
    fi

  else
    as_user cp "$DOTFILES_REPO/dotfiles/.config/niri/output-example.kdl" "$OUTPUT_KDL"
  fi

  # GTK Theme Symlinks (Fix internal links)
  GTK4="$HOME_DIR/.config/gtk-4.0"
  THEME="$HOME_DIR/.themes/adw-gtk3-dark/gtk-4.0"
  if [ -d "$GTK4" ]; then
      as_user rm -f "$GTK4/gtk.css" "$GTK4/gtk-dark.css"
      as_user ln -sf "$THEME/gtk-dark.css" "$GTK4/gtk-dark.css"
      as_user ln -sf "$THEME/gtk.css" "$GTK4/gtk.css"
  fi
  
  # Flatpak overrides
  if command -v flatpak &>/dev/null; then
    as_user flatpak override --user --filesystem="$HOME_DIR/.themes"
    as_user flatpak override --user --filesystem=xdg-config/gtk-4.0
    as_user flatpak override --user --filesystem=xdg-config/gtk-3.0
    as_user flatpak override --user --env=GTK_THEME=adw-gtk3-dark
    as_user flatpak override --user --filesystem=xdg-config/fontconfig
  fi
  success "Dotfiles Linked."
else
  warn "Dotfiles missing in repo directory."
fi

# ==============================================================================
# STEP 7: Wallpapers
# ==============================================================================
section "Step 6/9" "Wallpapers"
# 更新引用路径
if [ -d "$DOTFILES_REPO/wallpapers" ]; then
  as_user ln -sf "$DOTFILES_REPO/wallpapers" "$HOME_DIR/Pictures/Wallpapers"
  
  as_user mkdir -p "$HOME_DIR/Templates"
  as_user touch "$HOME_DIR/Templates/new"
  echo "#!/bin/bash" | as_user tee "$HOME_DIR/Templates/new.sh" >/dev/null
  as_user chmod +x "$HOME_DIR/Templates/new.sh"
  success "Installed."
fi
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