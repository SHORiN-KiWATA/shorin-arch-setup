#!/bin/bash

# ==============================================================================
# 03-user.sh - User Account & Environment Setup (Compatible with detect_target_user)
# ==============================================================================

# 1. 加载工具集
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

# 2. 检查 Root 权限
check_root

# ==============================================================================
# Phase 1: 用户识别与账户同步
# ==============================================================================
section "Phase 3" "User Account Setup"


# 清理缓存
if [ -f "/tmp/shorin_install_user" ]; then 
    rm "/tmp/shorin_install_user"
fi
# 调用全局函数，确定目标用户
detect_target_user

# 检查系统是否已经真的创建了这个账户
if id "$TARGET_USER" &>/dev/null; then
    success "User '${TARGET_USER}' already exists in the system."
    SKIP_CREATION=true
else
    log "User '${TARGET_USER}' does not exist. Preparing for creation..."
    SKIP_CREATION=false
fi

# ==============================================================================
# Phase 2: 账户创建、权限与密码配置
# ==============================================================================
section "Step 2/4" "Account & Privileges"

if [ "$SKIP_CREATION" = true ]; then
    log "Ensuring $TARGET_USER belongs to 'wheel' group..."
    if groups "$TARGET_USER" | grep -q "\bwheel\b"; then
        success "User is already in 'wheel' group."
    else
        log "Adding user to 'wheel' group..."
        exe usermod -aG wheel "$TARGET_USER"
    fi
else
    log "Creating new user '${TARGET_USER}'..."
    # 使用 -m 创建家目录，-g wheel 加入特权组
    exe useradd -m -G wheel -s /bin/bash "$TARGET_USER"
    
    log "Setting password for ${TARGET_USER}..."
    echo -e "   ${H_GRAY}--------------------------------------------------${NC}"
    # passwd 必须交互运行
    passwd "$TARGET_USER"
    PASSWORD_STATUS=$?
    echo -e "   ${H_GRAY}--------------------------------------------------${NC}"
    
    if [ $PASSWORD_STATUS -eq 0 ]; then 
        success "Password set successfully."
    else 
        error "Failed to set password. Script aborted."
        exit 1
    fi
fi

# 1. 配置 Sudoers
log "Configuring sudoers access..."

# A. 确保 wheel 组具备基础 sudo 权限 (需要密码)
if grep -q "^# %wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    exe sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    success "Uncommented %wheel in /etc/sudoers."
elif grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    success "Sudo access already enabled."
else
    log "Appending %wheel rule to /etc/sudoers..."
    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
    success "Sudo access configured."
fi

# B. 配置免密规则 (pacman, systemctl, sudoedit)
SUDO_CONF_FILE="/etc/sudoers.d/10-shorin-nopasswd"
log "Installing specialized NOPASSWD rules..."

cat << EOF > "$SUDO_CONF_FILE"
# Shorin Setup: Essential tools NOPASSWD for wheel group
%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/pacman, /usr/bin/systemctl, /usr/bin/sudoedit
EOF

exe chmod 440 "$SUDO_CONF_FILE"
success "Rules installed to $SUDO_CONF_FILE"

# 2. 配置 Faillock (防止输错密码锁定)
log "Configuring password lockout policy (faillock)..."
FAILLOCK_CONF="/etc/security/faillock.conf"
if [ -f "$FAILLOCK_CONF" ]; then
    exe sed -i 's/^#\?\s*deny\s*=.*/deny = 0/' "$FAILLOCK_CONF"
    success "Account lockout disabled (deny=0)."
fi

# ==============================================================================
# Phase 3: 生成 XDG 用户目录
# ==============================================================================
section "Step 3/4" "User Directories"

exe pacman -S --noconfirm --needed xdg-user-dirs

log "Generating XDG user directories..."
# 获取目标用户最新的家目录路径
REAL_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

# 强制以该用户身份运行更新
if exe runuser -u "$TARGET_USER" -- env LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 HOME="$REAL_HOME" xdg-user-dirs-update --force; then
    success "Directories created in $REAL_HOME."
else
    warn "Failed to generate standard directories."
fi

# ==============================================================================
# Phase 4: 环境配置 (PATH 与 .local/bin)
# ==============================================================================
section "Step 4/4" "Environment Setup"

LOCAL_BIN_PATH="$REAL_HOME/.local/bin"
log "Setting up user executable path: $LOCAL_BIN_PATH"

if exe runuser -u "$TARGET_USER" -- mkdir -p "$LOCAL_BIN_PATH"; then
    success "Directory ready."
else
    error "Failed to create ~/.local/bin"
fi

# 配置全局 PATH
PROFILE_SCRIPT="/etc/profile.d/user_local_bin.sh"
cat << 'EOF' > "$PROFILE_SCRIPT"
# Automatically add ~/.local/bin to PATH if it exists
if [ -d "$HOME/.local/bin" ]; then
    export PATH="$HOME/.local/bin:$PATH"
fi
EOF
exe chmod 644 "$PROFILE_SCRIPT"
success "PATH optimization script installed."

# ==============================================================================
# 完成
# ==============================================================================
hr
success "User setup module for '${TARGET_USER}' completed."
echo ""