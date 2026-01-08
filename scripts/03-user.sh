#!/bin/bash

# ==============================================================================
# 03-user.sh - User Creation & Configuration (Visual Fix)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

# ------------------------------------------------------------------------------
# 1. User Detection / Creation Logic
# ------------------------------------------------------------------------------
section "Phase 3" "User Account Setup"

EXISTING_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
MY_USERNAME=""
SKIP_CREATION=false

if [ -n "$EXISTING_USER" ]; then
    info_kv "Detected User" "$EXISTING_USER" "(UID 1000)"
    log "Using existing user configuration."
    MY_USERNAME="$EXISTING_USER"
    SKIP_CREATION=true
else
    warn "No standard user found (UID 1000)."
    
    while true; do
        echo ""
        # 使用 echo -n 打印普通提示，避免 read -p 的兼容性问题
        echo -ne "   Please enter new username: "
        read INPUT_USER
        
        # 去除可能误输入的空格
        INPUT_USER=$(echo "$INPUT_USER" | xargs)
        
        if [[ -z "$INPUT_USER" ]]; then
            warn "Username cannot be empty."
            continue
        fi

        # [FIX] 分离打印和读取，确保变量和颜色正确显示
        echo -ne "   Create user '${BOLD}${INPUT_USER}${NC}'? [Y/n] "
        read CONFIRM
        
        CONFIRM=${CONFIRM:-Y}
        
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            MY_USERNAME="$INPUT_USER"
            break
        else
            log "Cancelled. Please re-enter."
        fi
    done
fi

# Export username for next scripts
echo "$MY_USERNAME" > /tmp/shorin_install_user

# ------------------------------------------------------------------------------
# 2. Create User & Sudo
# ------------------------------------------------------------------------------
section "Step 2/3" "Account & Privileges"

if [ "$SKIP_CREATION" = true ]; then
    log "Checking permissions for $MY_USERNAME..."
    if groups "$MY_USERNAME" | grep -q "\bwheel\b"; then
        success "User is already in 'wheel' group."
    else
        log "Adding to 'wheel' group..."
        exe usermod -aG wheel "$MY_USERNAME"
    fi
else
    log "Creating new user..."
    exe useradd -m -g wheel "$MY_USERNAME"
    
    log "Setting password for $MY_USERNAME..."
    # passwd 需要交互，直接运行
    passwd "$MY_USERNAME"
    if [ $? -eq 0 ]; then 
        success "Password set."
    else 
        error "Failed to set password."
        exit 1
    fi
fi

# Configure Sudoers
log "Configuring sudoers..."
if grep -q "^# %wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    exe sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    success "Uncommented %wheel in /etc/sudoers."
elif grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    success "Sudo access already enabled."
else
    log "Appending %wheel rule..."
    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
    success "Sudo access configured."
fi

# ------------------------------------------------------------------------------
# 3. Generate User Directories
# ------------------------------------------------------------------------------
section "Step 3/3" "User Directories"

exe pacman -Syu --noconfirm --needed xdg-user-dirs

log "Generating directories (Downloads, Documents...)..."

# 1. 获取目标用户的真实 Home 目录路径
REAL_HOME=$(getent passwd "$MY_USERNAME" | cut -d: -f6)

# 2. 强制指定 HOME 环境变量运行更新命令
# 注意：这里加了 --force 确保即使配置文件已存在也能强制刷新目录结构
if exe runuser -u "$MY_USERNAME" -- env HOME="$REAL_HOME" xdg-user-dirs-update --force; then
    success "Directories created in $REAL_HOME."
else
    warn "Failed to generate directories."
fi

# ------------------------------------------------------------------------------
# fcitx5 post-config
# ------------------------------------------------------------------------------
section "fcitx5" "enable rime input method"
RIME_USER_DIR="$REAL_HOME/.local/share/fcitx5/rime"
exe runuser -u "$MY_USERNAME" -- mkdir -p "$RIME_USER_DIR"

cat <<EOF > "$RIME_USER_DIR/default.custom.yaml"
patch:
  __include: rime_ice_suggestion:/
EOF
chown -R "$MY_USERNAME" "$RIME_USER_DIR"

if grep -q "fcitx" /etc/environment; then
    echo "XMODIFIERS=@im=fcitx" >> /etc/environment
fi

log "Module 03 completed."
