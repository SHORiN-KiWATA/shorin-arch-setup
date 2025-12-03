#!/bin/bash

# ==============================================================================
# 06-kdeplasma-setup.sh - KDE Plasma Setup (Visual Enhanced + Logic Fix)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}

check_root

# --- Helper: Local Fallback (Fixed: Multiple files & Dependencies) ---
install_local_fallback() {
    local pkg_name="$1"
    local search_dir="$PARENT_DIR/compiled/$pkg_name"
    if [ ! -d "$search_dir" ]; then return 1; fi

    # 读取目录下所有包文件
    mapfile -t pkg_files < <(find "$search_dir" -maxdepth 1 -name "*.pkg.tar.zst")

    if [ ${#pkg_files[@]} -gt 0 ]; then
        warn "Using local fallback for '$pkg_name' (Found ${#pkg_files[@]} files)..."
        warn "Note: This uses cached binaries. If the app crashes, please rebuild from source."

        # 1. 收集依赖
        log "Resolving dependencies for local packages..."
        local all_deps=""
        for pkg_file in "${pkg_files[@]}"; do
            local deps=$(tar -xOf "$pkg_file" .PKGINFO | grep -E '^depend' | cut -d '=' -f 2 | xargs)
            if [ -n "$deps" ]; then all_deps="$all_deps $deps"; fi
        done
        
        # 2. 安装依赖 (使用 -Syu 确保系统同步)
        if [ -n "$all_deps" ]; then
            local unique_deps=$(echo "$all_deps" | tr ' ' '\n' | sort -u | tr '\n' ' ')
            # [UPDATE] Changed yay -S to yay -Syu
            if ! exe runuser -u "$TARGET_USER" -- yay -Syu --noconfirm --needed --asdeps $unique_deps; then
                error "Failed to install dependencies for local package '$pkg_name'."
                return 1
            fi
        fi

        # 3. 批量安装
        log "Installing local packages..."
        if exe runuser -u "$TARGET_USER" -- yay -U --noconfirm "${pkg_files[@]}"; then
            success "Installed from local."; return 0
        else
            error "Local install failed."; return 1
        fi
    else
        return 1
    fi
}

section "Phase 6" "KDE Plasma Environment"

# ------------------------------------------------------------------------------
# 0. Identify Target User
# ------------------------------------------------------------------------------
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
if [ -n "$DETECTED_USER" ]; then TARGET_USER="$DETECTED_USER"; else read -p "Target user: " TARGET_USER; fi
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# ------------------------------------------------------------------------------
# 1. Install KDE Plasma Base
# ------------------------------------------------------------------------------
section "Step 1/5" "Plasma Core"

log "Installing KDE Plasma Meta & Apps..."
KDE_PKGS="plasma-meta konsole dolphin kate firefox qt6-multimedia-ffmpeg pipewire-jack sddm"
exe pacman -Syu --noconfirm --needed $KDE_PKGS
success "KDE Plasma installed."

# ------------------------------------------------------------------------------
# 2. Software Store & Network (Smart Mirror Selection)
# ------------------------------------------------------------------------------
section "Step 2/5" "Software Store & Network"

log "Configuring Discover & Flatpak..."

exe pacman -Syu --noconfirm --needed flatpak flatpak-kcm
exe flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# --- Network Detection Logic ---
CURRENT_TZ=$(readlink -f /etc/localtime)
IS_CN_ENV=false

if [[ "$CURRENT_TZ" == *"Shanghai"* ]]; then
    IS_CN_ENV=true
    info_kv "Region" "China (Timezone)"
elif [ "$CN_MIRROR" == "1" ]; then
    IS_CN_ENV=true
    info_kv "Region" "China (Manual Env)"
elif [ "$DEBUG" == "1" ]; then
    IS_CN_ENV=true
    warn "DEBUG MODE: Forcing China Environment"
fi

# --- Mirror Configuration ---
if [ "$IS_CN_ENV" = true ]; then
    log "Enabling China Optimizations..."
    
    # Use utility function
    select_flathub_mirror

    
    success "Optimizations Enabled."
else
    log "Using Global Official Sources."
fi

# NOPASSWD for yay
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

# ------------------------------------------------------------------------------
# 3. Install Dependencies (Logic: Network First -> Retry -> Local Fallback)
# ------------------------------------------------------------------------------
section "Step 3/5" "KDE Dependencies"

LIST_FILE="$PARENT_DIR/kde-applist.txt"
FAILED_PACKAGES=()

if [ -f "$LIST_FILE" ]; then
    mapfile -t PACKAGE_ARRAY < <(grep -vE "^\s*#|^\s*$" "$LIST_FILE" | tr -d '\r')
    if [ ${#PACKAGE_ARRAY[@]} -gt 0 ]; then
        BATCH_LIST=""
        GIT_LIST=()
        for pkg in "${PACKAGE_ARRAY[@]}"; do
            if [[ "$pkg" == *"-git" ]]; then GIT_LIST+=("$pkg"); else BATCH_LIST+="$pkg "; fi
        done
        
        # Phase 1: Batch
        if [ -n "$BATCH_LIST" ]; then
            log "Batch Install..."
            # [UPDATE] Ensuring -Syu
            if ! exe runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
                warn "Batch failed. Retrying with mirror toggle..."
                if runuser -u "$TARGET_USER" -- git config --global --get url."https://gitclone.com/github.com/".insteadOf > /dev/null; then
                    runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
                else
                    runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
                fi
                if ! exe runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
                    error "Batch failed."
                else
                    success "Batch installed (on retry)."
                fi
            fi
        fi

        # Phase 2: Git (Network Priority)
        if [ ${#GIT_LIST[@]} -gt 0 ]; then
            log "Git Install..."
            for git_pkg in "${GIT_LIST[@]}"; do
                
                log "Installing '$git_pkg' (Network Build)..."
                
                # 1. Attempt Network Install
                # [UPDATE] Ensuring -Syu
                if exe runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                    success "Installed $git_pkg"
                else
                    warn "Network install failed for $git_pkg. Retrying with mirror toggle..."
                    
                    # 2. Retry with Mirror Toggle
                    if runuser -u "$TARGET_USER" -- git config --global --get url."https://gitclone.com/github.com/".insteadOf > /dev/null; then
                        runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
                    else
                        runuser -u "$TARGET_USER" -- git config --global url."https://gitclone.com/github.com/".insteadOf "https://github.com/"
                    fi

                    # [UPDATE] Ensuring -Syu
                    if exe runuser -u "$TARGET_USER" -- env GOPROXY=$GOPROXY yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "$git_pkg"; then
                        success "Installed $git_pkg (on retry)."
                    else
                        # 3. Final Fallback: Local Cache
                        warn "Network failed. Attempting local fallback for '$git_pkg'..."
                        if install_local_fallback "$git_pkg"; then
                            warn "INSTALLED FROM LOCAL CACHE. Rebuild recommended later."
                        else
                            error "Failed to install '$git_pkg' after all attempts."
                            FAILED_PACKAGES+=("$git_pkg")
                        fi
                    fi
                fi
            done
        fi
        
        # Report Failures
        if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
            DOCS_DIR="$HOME_DIR/Documents"
            REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"
            if [ ! -d "$DOCS_DIR" ]; then runuser -u "$TARGET_USER" -- mkdir -p "$DOCS_DIR"; fi
            
            echo "--- Installation Failed Report $(date) ---" >> "$REPORT_FILE"
            printf "%s\n" "${FAILED_PACKAGES[@]}" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
            warn "Some packages failed. List saved to: $REPORT_FILE"
        fi
    fi
else
    warn "kde-applist.txt not found."
fi

# ------------------------------------------------------------------------------
# 4. Dotfiles Deployment (FIXED CP-RF)
# ------------------------------------------------------------------------------
section "Step 4/5" "KDE Config Deployment"

DOTFILES_SOURCE="$PARENT_DIR/kde-dotfiles"

if [ -d "$DOTFILES_SOURCE" ]; then
    log "Deploying KDE configurations..."
    
    # 1. Backup Existing .config
    BACKUP_NAME="config_backup_kde_$(date +%s).tar.gz"
    if [ -d "$HOME_DIR/.config" ]; then
        log "Backing up ~/.config to $BACKUP_NAME..."
        exe runuser -u "$TARGET_USER" -- tar -czf "$HOME_DIR/$BACKUP_NAME" -C "$HOME_DIR" .config
    fi
    
    # 2. Explicitly Copy .config and .local
    
    # --- Process .config ---
    if [ -d "$DOTFILES_SOURCE/.config" ]; then
        log "Merging .config..."
        if [ ! -d "$HOME_DIR/.config" ]; then mkdir -p "$HOME_DIR/.config"; fi
        
        exe cp -rf "$DOTFILES_SOURCE/.config/"* "$HOME_DIR/.config/" 2>/dev/null || true
        exe cp -rf "$DOTFILES_SOURCE/.config/." "$HOME_DIR/.config/" 2>/dev/null || true
        
        log "Fixing permissions for .config..."
        exe chown -R "$TARGET_USER:$TARGET_USER" "$HOME_DIR/.config"
    fi

    # --- Process .local ---
    if [ -d "$DOTFILES_SOURCE/.local" ]; then
        log "Merging .local..."
        if [ ! -d "$HOME_DIR/.local" ]; then mkdir -p "$HOME_DIR/.local"; fi
        
        exe cp -rf "$DOTFILES_SOURCE/.local/"* "$HOME_DIR/.local/" 2>/dev/null || true
        exe cp -rf "$DOTFILES_SOURCE/.local/." "$HOME_DIR/.local/" 2>/dev/null || true
        
        log "Fixing permissions for .local..."
        exe chown -R "$TARGET_USER:$TARGET_USER" "$HOME_DIR/.local"
    fi
    
    success "KDE Dotfiles applied and permissions fixed."
else
    warn "Folder 'kde-dotfiles' not found in repo. Skipping config."
fi

# ------------------------------------------------------------------------------
# 4.5 Deploy Resource Files (README)
# ------------------------------------------------------------------------------
log "Deploying desktop resources..."

SOURCE_README="$PARENT_DIR/resources/KDE-README.txt"
DESKTOP_DIR="$HOME_DIR/Desktop"

# Ensure Desktop exists (Create as user)
if [ ! -d "$DESKTOP_DIR" ]; then
    exe runuser -u "$TARGET_USER" -- mkdir -p "$DESKTOP_DIR"
fi

if [ -f "$SOURCE_README" ]; then
    log "Copying KDE-README.txt to Desktop..."
    exe cp "$SOURCE_README" "$DESKTOP_DIR/"
    exe chown "$TARGET_USER:$TARGET_USER" "$DESKTOP_DIR/KDE-README.txt"
    success "Readme deployed."
else
    warn "resources/KDE-README.txt not found. Skipping."
fi

# ------------------------------------------------------------------------------
# 4.5 Deploy Resource Files (README)
# ------------------------------------------------------------------------------
log "Deploying desktop resources..."

SOURCE_README="$PARENT_DIR/resources/KDE-README.txt"
DESKTOP_DIR="$HOME_DIR/Desktop"

if [ ! -d "$DESKTOP_DIR" ]; then
    exe runuser -u "$TARGET_USER" -- mkdir -p "$DESKTOP_DIR"
fi

if [ -f "$SOURCE_README" ]; then
    log "Copying KDE-README.txt..."
    exe cp "$SOURCE_README" "$DESKTOP_DIR/"
    exe chown "$TARGET_USER:$TARGET_USER" "$DESKTOP_DIR/KDE-README.txt"
    success "Readme deployed."
else
    warn "resources/KDE-README.txt not found."
fi

# ------------------------------------------------------------------------------
# 5. Enable SDDM (FIXED THEME)
# ------------------------------------------------------------------------------
section "Step 5/5" "Enable Display Manager"

log "Configuring SDDM Theme to Breeze..."
exe mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/theme.conf <<EOF
[Theme]
Current=breeze
EOF
log "Theme set to 'breeze'."

log "Enabling SDDM..."
exe systemctl enable sddm
success "SDDM enabled. Will start on reboot."

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
section "Cleanup" "Restoring State"
rm -f "$SUDO_TEMP_FILE"
runuser -u "$TARGET_USER" -- git config --global --unset url."https://gitclone.com/github.com/".insteadOf
sed -i '/GOPROXY=https:\/\/goproxy.cn,direct/d' /etc/environment
success "Done."

log "Module 06 completed."