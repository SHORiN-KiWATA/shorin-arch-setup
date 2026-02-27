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

cleanup_minegrub() {
    local minegrub_found=false
    
    if [ -f "/etc/grub.d/05_twomenus" ] || [ -f "/boot/grub/mainmenu.cfg" ]; then
        minegrub_found=true
        log "Found Minegrub artifacts. Cleaning up..."
        [ -f "/etc/grub.d/05_twomenus" ] && exe rm -f /etc/grub.d/05_twomenus
        [ -f "/boot/grub/mainmenu.cfg" ] && exe rm -f /boot/grub/mainmenu.cfg
    fi
    
    if command -v grub-editenv >/dev/null 2>&1; then
        if grub-editenv - list 2>/dev/null | grep -q "^config_file="; then
            minegrub_found=true
            log "Unsetting Minegrub GRUB environment variable..."
            exe grub-editenv - unset config_file
        fi
    fi
    
    if [ "$minegrub_found" == "true" ]; then
        success "Minegrub double-menu configuration completely removed."
    fi
}

# ------------------------------------------------------------------------------
# 1. Advanced GRUB Configuration
# ------------------------------------------------------------------------------
section "Step 1/7" "General GRUB Settings"

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
# 2. Sync Themes to System
# ------------------------------------------------------------------------------
section "Step 2/7" "Sync Themes to System Directory"

SOURCE_BASE="$PARENT_DIR/grub-themes"
DEST_DIR="/boot/grub/themes"

if [ ! -d "$DEST_DIR" ]; then 
    exe mkdir -p "$DEST_DIR"
fi

if [ -d "$SOURCE_BASE" ]; then
    log "Syncing repository themes to $DEST_DIR..."
    for dir in "$SOURCE_BASE"/*; do
        if [ -d "$dir" ] && [ -f "$dir/theme.txt" ]; then
            THEME_BASENAME=$(basename "$dir")
            if [ ! -d "$DEST_DIR/$THEME_BASENAME" ]; then
                log "Copying $THEME_BASENAME..."
                exe cp -r "$dir" "$DEST_DIR/"
            fi
        fi
    done
    success "Local themes synced."
else
    warn "Directory 'grub-themes' not found in repo. Only online/existing themes available."
fi

log "Scanning $DEST_DIR for available themes..."
THEME_PATHS=()
THEME_NAMES=()

mapfile -t FOUND_DIRS < <(find "$DEST_DIR" -mindepth 1 -maxdepth 1 -type d | sort 2>/dev/null || true)

for dir in "${FOUND_DIRS[@]:-}"; do
    if [ -n "$dir" ] && [ -f "$dir/theme.txt" ]; then
        DIR_NAME=$(basename "$dir")
        if [[ "$DIR_NAME" != "minegrub" && "$DIR_NAME" != "minegrub-world-selection" ]]; then
            THEME_PATHS+=("$dir")
            THEME_NAMES+=("$DIR_NAME")
        fi
    fi
done

if [ ${#THEME_NAMES[@]} -eq 0 ]; then
    log "No valid local theme folders found. Proceeding to online menu."
fi

# ------------------------------------------------------------------------------
# 3. Select Theme (TUI Menu)
# ------------------------------------------------------------------------------
section "Step 3/7" "Theme Selection"

INSTALL_MINEGRUB=false
SKIP_THEME=false

MINEGRUB_OPTION_NAME="Minegrub"
SKIP_OPTION_NAME="No theme (Skip/Clear)"

MINEGRUB_IDX=$((${#THEME_NAMES[@]} + 1))
SKIP_IDX=$((${#THEME_NAMES[@]} + 2))

TITLE_TEXT="Select GRUB Theme (60s Timeout)"
LINE_STR="───────────────────────────────────────────────────────"

echo -e "\n${H_PURPLE}╭${LINE_STR}${NC}"
echo -e "${H_PURPLE}│${NC}   ${BOLD}${TITLE_TEXT}${NC}"
echo -e "${H_PURPLE}├${LINE_STR}${NC}"

for i in "${!THEME_NAMES[@]}"; do
    NAME="${THEME_NAMES[$i]}"
    DISPLAY_NAME=$(echo "$NAME" | sed -E 's/^[0-9]+//')
    DISPLAY_IDX=$((i+1))
    
    if [ "$i" -eq 0 ]; then
        COLOR_STR=" ${H_CYAN}[$DISPLAY_IDX]${NC} ${DISPLAY_NAME} - ${H_GREEN}Default${NC}"
    else
        COLOR_STR=" ${H_CYAN}[$DISPLAY_IDX]${NC} ${DISPLAY_NAME}"
    fi
    echo -e "${H_PURPLE}│${NC} ${COLOR_STR}"
done

MG_COLOR_STR=" ${H_CYAN}[$MINEGRUB_IDX]${NC} ${MINEGRUB_OPTION_NAME}"
echo -e "${H_PURPLE}│${NC} ${MG_COLOR_STR}"

SKIP_COLOR_STR=" ${H_CYAN}[$SKIP_IDX]${NC} ${H_YELLOW}${SKIP_OPTION_NAME}${NC}"
echo -e "${H_PURPLE}│${NC} ${SKIP_COLOR_STR}"

echo -e "${H_PURPLE}╰${LINE_STR}${NC}\n"

echo -ne "   ${H_YELLOW}Enter choice [1-$SKIP_IDX]: ${NC}"
read -t 60 USER_CHOICE || true
if [ -z "${USER_CHOICE:-}" ]; then echo ""; fi
USER_CHOICE=${USER_CHOICE:-1}

if ! [[ "$USER_CHOICE" =~ ^[0-9]+$ ]] || [ "$USER_CHOICE" -lt 1 ] || [ "$USER_CHOICE" -gt "$SKIP_IDX" ]; then
    log "Invalid choice or timeout. Defaulting to first option..."
    USER_CHOICE=1
fi

if [ "$USER_CHOICE" -eq "$SKIP_IDX" ]; then
    SKIP_THEME=true
    info_kv "Selected" "None (Clear Theme)"
elif [ "$USER_CHOICE" -eq "$MINEGRUB_IDX" ]; then
    INSTALL_MINEGRUB=true
    info_kv "Selected" "Minegrub (Online Repository)"
else
    SELECTED_INDEX=$((USER_CHOICE-1))
    if [ -n "${THEME_NAMES[$SELECTED_INDEX]:-}" ]; then
        THEME_PATH="${THEME_PATHS[$SELECTED_INDEX]}/theme.txt"
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
section "Step 4/7" "Theme Configuration"

GRUB_CONF="/etc/default/grub"

if [ "$SKIP_THEME" == "true" ]; then
    log "Clearing GRUB theme configuration..."
    cleanup_minegrub
    
    if [ -f "$GRUB_CONF" ]; then
        if grep -q "^GRUB_THEME=" "$GRUB_CONF"; then
            exe sed -i 's|^GRUB_THEME=|#GRUB_THEME=|' "$GRUB_CONF"
            success "Disabled existing GRUB_THEME in configuration."
        else
            log "No active GRUB_THEME found to disable."
        fi
    fi

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
        [ -n "$TEMP_MG_DIR" ] && rm -rf "$TEMP_MG_DIR"
    fi

else
    cleanup_minegrub

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
        success "Configured GRUB to use theme: $THEME_NAME"
    else
        error "$GRUB_CONF not found."
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# 5. Add Shutdown/Reboot Menu Entries
# ------------------------------------------------------------------------------
section "Step 5/7" "Menu Entries"
log "Adding Power Options to GRUB menu..."

cp /etc/grub.d/40_custom /etc/grub.d/99_custom
echo 'menuentry "Reboot"' {reboot} >> /etc/grub.d/99_custom
echo 'menuentry "Shutdown"' {halt} >> /etc/grub.d/99_custom

success "Added grub menuentry 99-shutdown"

# ------------------------------------------------------------------------------
# 7. Apply Changes
# ------------------------------------------------------------------------------
section "Step 7/7" "Apply Changes"
log "Generating new GRUB configuration..."

if exe grub-mkconfig -o /boot/grub/grub.cfg; then
    success "GRUB updated successfully."
else
    error "Failed to update GRUB."
    warn "You may need to run 'grub-mkconfig' manually."
fi

log "Module 07 completed."