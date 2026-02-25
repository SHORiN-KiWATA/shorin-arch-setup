#!/bin/bash

# ==============================================================================
# 07-grub-theme.sh - GRUB Theming & Advanced Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

# ------------------------------------------------------------------------------
# 0. Pre-check: Is GRUB installed?
# ------------------------------------------------------------------------------
if ! command -v grub-mkconfig >/dev/null 2>&1; then
    echo ""
    warn "GRUB (grub-mkconfig) not found on this system."
    log "Skipping GRUB theme installation."
    exit 0
fi

section "Phase 7" "GRUB Customization & Theming"

# --- Helper Functions ---

set_grub_value() {
    local key="$1"
    local value="$2"
    local conf_file="/etc/default/grub"
    local escaped_value
    escaped_value=$(printf '%s\n' "$value" | sed 's,[\/&],\\&,g')

    if grep -q -E "^#\s*$key=" "$conf_file"; then
        exe sed -i -E "s,^#\s*$key=.*,$key=\"$escaped_value\"," "$conf_file"
    elif grep -q -E "^$key=" "$conf_file"; then
        exe sed -i -E "s,^$key=.*,$key=\"$escaped_value\"," "$conf_file"
    else
        log "Appending new key: $key"
        echo "$key=\"$escaped_value\"" >> "$conf_file"
    fi
}

manage_kernel_param() {
    local action="$1"
    local param="$2"
    local conf_file="/etc/default/grub"
    local line
    
    # 增加对 grep 失败的宽容度，防止无默认值时报错
    line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$conf_file" || true)
    
    local params
    params=$(echo "$line" | sed -e 's/GRUB_CMDLINE_LINUX_DEFAULT=//' -e 's/"//g')
    local param_key
    if [[ "$param" == *"="* ]]; then param_key="${param%%=*}"; else param_key="$param"; fi
    params=$(echo "$params" | sed -E "s/\b${param_key}(=[^ ]*)?\b//g")

    if [ "$action" == "add" ]; then params="$params $param"; fi

    params=$(echo "$params" | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    exe sed -i "s,^GRUB_CMDLINE_LINUX_DEFAULT=.*,GRUB_CMDLINE_LINUX_DEFAULT=\"$params\"," "$conf_file"
}

# ------------------------------------------------------------------------------
# 1. Advanced GRUB Configuration
# ------------------------------------------------------------------------------
section "Step 1/5" "General GRUB Settings"

if [ -L "/boot/grub" ]; then
    LINK_TARGET=$(readlink -f "/boot/grub" || true)
    
    if [[ "$LINK_TARGET" == "/efi/grub" ]] || [[ "$LINK_TARGET" == "/boot/efi/grub" ]]; then
        log "Detected /boot/grub linked to ESP ($LINK_TARGET). Enabling GRUB savedefault..."
        set_grub_value "GRUB_DEFAULT" "saved"
        set_grub_value "GRUB_SAVEDEFAULT" "true"
    else
        log "Skipping savedefault: /boot/grub links to $LINK_TARGET (not /efi/grub or /boot/efi/grub)."
    fi
else
    log "Skipping savedefault: /boot/grub is not a symbolic link."
fi

log "Configuring kernel boot parameters for detailed logs and performance..."
manage_kernel_param "remove" "quiet"
manage_kernel_param "remove" "splash"
manage_kernel_param "add" "loglevel=5"
manage_kernel_param "add" "nowatchdog"

# CPU Watchdog Logic (Safely handled via awk to prevent pipe failures)
CPU_VENDOR=$(LC_ALL=C lscpu 2>/dev/null | awk '/Vendor ID:/ {print $3}' || true)
if [ "${CPU_VENDOR:-}" == "GenuineIntel" ]; then
    log "Intel CPU detected. Disabling iTCO_wdt watchdog."
    manage_kernel_param "add" "modprobe.blacklist=iTCO_wdt"
elif [ "${CPU_VENDOR:-}" == "AuthenticAMD" ]; then
    log "AMD CPU detected. Disabling sp5100_tco watchdog."
    manage_kernel_param "add" "modprobe.blacklist=sp5100_tco"
fi

success "Kernel parameters updated."

# ------------------------------------------------------------------------------
# 2. Detect Themes
# ------------------------------------------------------------------------------
section "Step 2/5" "Theme Detection"
log "Scanning for themes in 'grub-themes' folder..."

SOURCE_BASE="$PARENT_DIR/grub-themes"
DEST_DIR="/boot/grub/themes"

# 初始化数组，确保即使目录不存在也不会引发未绑定变量错误
THEME_PATHS=()
THEME_NAMES=()

if [ ! -d "$SOURCE_BASE" ]; then
    warn "Directory 'grub-themes' not found in repo. Only online themes will be available."
else
    mapfile -t FOUND_DIRS < <(find "$SOURCE_BASE" -mindepth 1 -maxdepth 1 -type d | sort 2>/dev/null || true)
    
    for dir in "${FOUND_DIRS[@]:-}"; do
        if [ -n "$dir" ] && [ -f "$dir/theme.txt" ]; then
            THEME_PATHS+=("$dir")
            THEME_NAMES+=("$(basename "$dir")")
        fi
    done
fi

if [ ${#THEME_NAMES[@]} -eq 0 ]; then
    log "No valid local theme folders found. Proceeding to online menu."
fi

# ------------------------------------------------------------------------------
# 3. Select Theme (TUI Menu)
# ------------------------------------------------------------------------------
section "Step 3/5" "Theme Selection"

INSTALL_MINEGRUB=false
SKIP_THEME=false

MINEGRUB_OPTION_NAME="Minegrub"
SKIP_OPTION_NAME="No theme (Skip)"

# 动态计算菜单选项数量和索引
MINEGRUB_IDX=$((${#THEME_NAMES[@]} + 1))
SKIP_IDX=$((${#THEME_NAMES[@]} + 2))

TITLE_TEXT="Select GRUB Theme (60s Timeout)"
MAX_LEN=${#TITLE_TEXT}

# 计算本地主题名称最大长度
for name in "${THEME_NAMES[@]:-}"; do
    ITEM_LEN=$((${#name} + 20))
    if (( ITEM_LEN > MAX_LEN )); then MAX_LEN=$ITEM_LEN; fi
done

# 计算新增选项长度
MINEGRUB_LEN=$((${#MINEGRUB_OPTION_NAME} + 10))
if (( MINEGRUB_LEN > MAX_LEN )); then MAX_LEN=$MINEGRUB_LEN; fi

SKIP_LEN=$((${#SKIP_OPTION_NAME} + 10))
if (( SKIP_LEN > MAX_LEN )); then MAX_LEN=$SKIP_LEN; fi

MENU_WIDTH=$((MAX_LEN + 4))
LINE_STR=""; printf -v LINE_STR "%*s" "$MENU_WIDTH" ""; LINE_STR=${LINE_STR// /─}

echo -e "\n${H_PURPLE}╭${LINE_STR}╮${NC}"
TITLE_PADDING_LEN=$(( (MENU_WIDTH - ${#TITLE_TEXT}) / 2 ))
RIGHT_PADDING_LEN=$((MENU_WIDTH - ${#TITLE_TEXT} - TITLE_PADDING_LEN))
T_PAD_L=""; printf -v T_PAD_L "%*s" "$TITLE_PADDING_LEN" ""
T_PAD_R=""; printf -v T_PAD_R "%*s" "$RIGHT_PADDING_LEN" ""
echo -e "${H_PURPLE}│${NC}${T_PAD_L}${BOLD}${TITLE_TEXT}${NC}${T_PAD_R}${H_PURPLE}│${NC}"
echo -e "${H_PURPLE}├${LINE_STR}┤${NC}"

# 打印本地主题列表
for i in "${!THEME_NAMES[@]}"; do
    NAME="${THEME_NAMES[$i]}"
    DISPLAY_IDX=$((i+1))
    
    if [ "$i" -eq 0 ]; then
        COLOR_STR=" ${H_CYAN}[$DISPLAY_IDX]${NC} ${NAME} - ${H_GREEN}Default${NC}"
        RAW_STR=" [$DISPLAY_IDX] $NAME - Default"
    else
        COLOR_STR=" ${H_CYAN}[$DISPLAY_IDX]${NC} ${NAME}"
        RAW_STR=" [$DISPLAY_IDX] $NAME"
    fi
    PADDING=$((MENU_WIDTH - ${#RAW_STR}))
    PAD_STR=""; if [ "$PADDING" -gt 0 ]; then printf -v PAD_STR "%*s" "$PADDING" ""; fi
    echo -e "${H_PURPLE}│${NC}${COLOR_STR}${PAD_STR}${H_PURPLE}│${NC}"
done

# 打印 Minegrub 选项 (去掉了高亮色和括号说明，保持普通样式)
MG_RAW_STR=" [$MINEGRUB_IDX] $MINEGRUB_OPTION_NAME"
MG_COLOR_STR=" ${H_CYAN}[$MINEGRUB_IDX]${NC} ${MINEGRUB_OPTION_NAME}"
MG_PADDING=$((MENU_WIDTH - ${#MG_RAW_STR}))
MG_PAD_STR=""; if [ "$MG_PADDING" -gt 0 ]; then printf -v MG_PAD_STR "%*s" "$MG_PADDING" ""; fi
echo -e "${H_PURPLE}│${NC}${MG_COLOR_STR}${MG_PAD_STR}${H_PURPLE}│${NC}"

# 打印“不安装”选项
SKIP_RAW_STR=" [$SKIP_IDX] $SKIP_OPTION_NAME"
SKIP_COLOR_STR=" ${H_CYAN}[$SKIP_IDX]${NC} ${H_YELLOW}${SKIP_OPTION_NAME}${NC}"
SKIP_PADDING=$((MENU_WIDTH - ${#SKIP_RAW_STR}))
SKIP_PAD_STR=""; if [ "$SKIP_PADDING" -gt 0 ]; then printf -v SKIP_PAD_STR "%*s" "$SKIP_PADDING" ""; fi
echo -e "${H_PURPLE}│${NC}${SKIP_COLOR_STR}${SKIP_PAD_STR}${H_PURPLE}│${NC}"

echo -e "${H_PURPLE}╰${LINE_STR}╯${NC}\n"

echo -ne "   ${H_YELLOW}Enter choice [1-$SKIP_IDX]: ${NC}"
read -t 60 USER_CHOICE || true
if [ -z "${USER_CHOICE:-}" ]; then echo ""; fi
USER_CHOICE=${USER_CHOICE:-1}

# 验证输入逻辑
if ! [[ "$USER_CHOICE" =~ ^[0-9]+$ ]] || [ "$USER_CHOICE" -lt 1 ] || [ "$USER_CHOICE" -gt "$SKIP_IDX" ]; then
    log "Invalid choice or timeout. Defaulting to first option..."
    USER_CHOICE=1
fi

if [ "$USER_CHOICE" -eq "$SKIP_IDX" ]; then
    SKIP_THEME=true
    info_kv "Selected" "None (Skip Theme Installation)"
elif [ "$USER_CHOICE" -eq "$MINEGRUB_IDX" ]; then
    INSTALL_MINEGRUB=true
    info_kv "Selected" "Minegrub (Online Repository)"
else
    SELECTED_INDEX=$((USER_CHOICE-1))
    # 再次确认本地数组越界安全
    if [ -n "${THEME_NAMES[$SELECTED_INDEX]:-}" ]; then
        THEME_SOURCE="${THEME_PATHS[$SELECTED_INDEX]}"
        THEME_NAME="${THEME_NAMES[$SELECTED_INDEX]}"
        info_kv "Selected" "Local: $THEME_NAME"
    else
        warn "Local theme array empty but selected. Defaulting to Minegrub."
        INSTALL_MINEGRUB=true
    fi
fi

# ------------------------------------------------------------------------------
# 4. Install & Configure Theme
# ------------------------------------------------------------------------------
section "Step 4/5" "Theme Installation"

if [ "$SKIP_THEME" == "true" ]; then
    log "Skipping theme copy and configuration as requested."

elif [ "$INSTALL_MINEGRUB" == "true" ]; then
    log "Preparing to install Minegrub theme..."
    
    if ! command -v git >/dev/null 2>&1; then
        error "'git' is required to clone Minegrub but was not found. Skipping."
    else
        TEMP_MG_DIR=$(mktemp -d -t minegrub_install_XXXXXX)
        
        log "Cloning Lxtharia/double-minegrub-menu..."
        if exe git clone --depth 1 "https://github.com/Lxtharia/double-minegrub-menu.git" "$TEMP_MG_DIR"; then
            if [ -f "$TEMP_MG_DIR/install.sh" ]; then
                log "Executing Minegrub install.sh..."
                # 使用 subshell 执行，避免污染当前 shell 环境变量和工作目录
                (
                    cd "$TEMP_MG_DIR" || exit 1
                    exe chmod +x install.sh
                    exe ./install.sh
                )
                if [ $? -eq 0 ]; then
                    success "Minegrub theme successfully installed via its script."
                else
                    error "Minegrub install.sh exited with an error."
                fi
            else
                error "install.sh not found in the cloned repository!"
            fi
        else
            error "Failed to clone Minegrub repository."
        fi
        
        # 安全清理临时目录
        [ -n "$TEMP_MG_DIR" ] && rm -rf "$TEMP_MG_DIR"
    fi

else
    # 原本的本地主题安装逻辑
    if [ ! -d "$DEST_DIR" ]; then exe mkdir -p "$DEST_DIR"; fi
    if [ -d "$DEST_DIR/$THEME_NAME" ]; then
        log "Removing existing version..."
        exe rm -rf "$DEST_DIR/$THEME_NAME"
    fi

    exe cp -r "$THEME_SOURCE" "$DEST_DIR/"

    if [ -f "$DEST_DIR/$THEME_NAME/theme.txt" ]; then
        success "Theme installed."
    else
        error "Failed to copy theme files."
        exit 1
    fi

    GRUB_CONF="/etc/default/grub"
    THEME_PATH="$DEST_DIR/$THEME_NAME/theme.txt"

    if [ -f "$GRUB_CONF" ]; then
        if grep -q "^GRUB_THEME=" "$GRUB_CONF"; then
            exe sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"$THEME_PATH\"|" "$GRUB_CONF"
        elif grep -q "^#GRUB_THEME=" "$GRUB_CONF"; then
            exe sed -i "s|^#GRUB_THEME=.*|GRUB_THEME=\"$THEME_PATH\"|" "$GRUB_CONF"
        else
            echo "GRUB_THEME=\"$THEME_PATH\"" >> "$GRUB_CONF"
        fi
        
        if grep -q "^GRUB_TERMINAL_OUTPUT=\"console\"" "$GRUB_CONF"; then
            exe sed -i 's/^GRUB_TERMINAL_OUTPUT="console"/#GRUB_TERMINAL_OUTPUT="console"/' "$GRUB_CONF"
        fi
        
        if ! grep -q "^GRUB_GFXMODE=" "$GRUB_CONF"; then
            echo 'GRUB_GFXMODE=auto' >> "$GRUB_CONF"
        fi
        success "Configured GRUB to use local theme: $THEME_NAME"
    else
        error "$GRUB_CONF not found."
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# 5. Add Shutdown/Reboot Menu Entries
# ------------------------------------------------------------------------------
section "Step 5/5" "Menu Entries & Apply"
log "Adding Power Options to GRUB menu..."

cp /etc/grub.d/40_custom /etc/grub.d/99_custom
echo 'menuentry "Reboot"' {reboot} >> /etc/grub.d/99_custom
echo 'menuentry "Shutdown"' {halt} >> /etc/grub.d/99_custom

success "Added grub menuentry 99-shutdown"

# ------------------------------------------------------------------------------
# 6. Apply Changes
# ------------------------------------------------------------------------------
log "Generating new GRUB configuration..."

if exe grub-mkconfig -o /boot/grub/grub.cfg; then
    success "GRUB updated successfully."
else
    error "Failed to update GRUB."
    warn "You may need to run 'grub-mkconfig' manually."
fi

log "Module 07 completed."