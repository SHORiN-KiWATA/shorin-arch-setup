#!/bin/bash
set -euo pipefail
# ==============================================================================
# 03-user.sh - User Account & Environment Setup
# ==============================================================================

# 1. 加载工具集
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

# 2. 检查 Root 权限
check_root

# ==============================================================================
# Phase 1: 用户检测与创建逻辑
# ==============================================================================
section "Phase 3" "User Account Setup"

# 检测是否已存在普通用户 (UID 1000)
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
    
    # 交互式输入用户名循环
    while true; do
        echo ""
        # 使用 echo -ne 配合颜色变量实现漂亮的输入提示
        echo -ne "   ${ARROW} ${H_YELLOW}Please enter new username:${NC} "
        read INPUT_USER
        
        # 去除前后空格
        INPUT_USER=$(echo "$INPUT_USER" | xargs)
        
        # 空值检查
        if [[ -z "$INPUT_USER" ]]; then
            warn "Username cannot be empty."
            continue
        fi

        # 确认提示
        echo -ne "   ${INFO} Create user '${BOLD}${H_CYAN}${INPUT_USER}${NC}'? [Y/n] "
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

# 将用户名导出到临时文件，供后续脚本 (如安装桌面环境时) 使用
echo "$MY_USERNAME" > /tmp/shorin_install_user

# ==============================================================================
# Phase 2: 账户权限与密码配置
# ==============================================================================
section "Step 2/4" "Account & Privileges"

if [ "$SKIP_CREATION" = true ]; then
    log "Checking permissions for $MY_USERNAME..."
    if groups "$MY_USERNAME" | grep -q "\bwheel\b"; then
        success "User is already in 'wheel' group."
    else
        log "Adding user to 'wheel' group..."
        exe usermod -aG wheel "$MY_USERNAME"
    fi
else
    log "Creating new user '${MY_USERNAME}'..."
    exe useradd -m -g wheel -s /bin/bash "$MY_USERNAME"
    
    log "Setting password for ${MY_USERNAME}..."
    echo -e "   ${H_GRAY}--------------------------------------------------${NC}"
    # passwd 必须要交互，不能用 exe 包装
    passwd "$MY_USERNAME"
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
if grep -q "^# %wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    # 使用 sed 去掉注释
    exe sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    success "Uncommented %wheel in /etc/sudoers."
elif grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    success "Sudo access already enabled."
else
    # 如果找不到标准行，则追加
    log "Appending %wheel rule to /etc/sudoers..."
    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
    success "Sudo access configured."
fi

# 2. 配置 Faillock (防止输错密码锁定) [新增部分]
log "Configuring password lockout policy (faillock)..."
FAILLOCK_CONF="/etc/security/faillock.conf"

if [ -f "$FAILLOCK_CONF" ]; then
    # 使用 sed 匹配被注释的(# deny =) 或者未注释的(deny =) 行，统一改为 deny = 0
    # 正则解释: ^#\? 匹配开头可选的井号; \s* 匹配可选空格
    exe sed -i 's/^#\?\s*deny\s*=.*/deny = 0/' "$FAILLOCK_CONF"
    success "Account lockout disabled (deny=0)."
else
    # 极少数情况该文件不存在，虽然在 Arch 中默认是有这个文件的
    warn "File $FAILLOCK_CONF not found. Skipping lockout config."
fi

# ==============================================================================
# Phase 3: 生成 XDG 用户目录
# ==============================================================================
section "Step 3/4" "User Directories"

# 安装工具
exe pacman -Syu --noconfirm --needed xdg-user-dirs

log "Generating directories (Downloads, Documents, etc.)..."

# 获取用户真实的 Home 目录 (处理用户可能更改过 home 的情况)
REAL_HOME=$(getent passwd "$MY_USERNAME" | cut -d: -f6)

# 强制以该用户身份运行更新命令
# 注意：使用 env 设置 HOME 和 LANG 确保目录名为英文 (arch 习惯)
if exe runuser -u "$MY_USERNAME" -- env LANG=en_US.UTF-8 HOME="$REAL_HOME" xdg-user-dirs-update --force; then
    success "Directories created in $REAL_HOME."
else
    warn "Failed to generate standard directories."
fi

# ==============================================================================
# Phase 4: 环境配置 (PATH 与 .local/bin)
# ==============================================================================
section "Step 4/4" "Environment Setup"

# 1. 创建 ~/.local/bin
# 关键点：使用 runuser 确保文件夹归属权是用户，而不是 root
LOCAL_BIN_PATH="$REAL_HOME/.local/bin"

log "Creating user executable directory..."
info_kv "Target" "$LOCAL_BIN_PATH"

if exe runuser -u "$MY_USERNAME" -- mkdir -p "$LOCAL_BIN_PATH"; then
    success "Created directory (Ownership: $MY_USERNAME)"
else
    error "Failed to create ~/.local/bin"
fi

# 2. 配置全局 PATH (/etc/profile.d/)
PROFILE_SCRIPT="/etc/profile.d/user_local_bin.sh"
log "Configuring automatic PATH detection..."

# 写入配置脚本
cat << 'EOF' > "$PROFILE_SCRIPT"
# Automatically add ~/.local/bin to PATH if it exists
if [ -d "$HOME/.local/bin" ]; then
    export PATH="$HOME/.local/bin:$PATH"
fi
EOF

# 设置权限 (rw-r--r--)
exe chmod 644 "$PROFILE_SCRIPT"

if [ -f "$PROFILE_SCRIPT" ]; then
    success "PATH script installed to /etc/profile.d/"
    info_kv "Effect" "Requires re-login"
else
    warn "Failed to create profile.d script."
fi

# ==============================================================================
# 完成
# ==============================================================================
hr
success "User setup module completed."
echo -e "   ${DIM}User '${MY_USERNAME}' is ready for Desktop Environment setup.${NC}"
echo ""