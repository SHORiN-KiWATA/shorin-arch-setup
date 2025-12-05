#!/bin/bash

# ==============================================================================
# Shorin Arch Setup - Main Installer (v1.1))
# ==============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
STATE_FILE="$BASE_DIR/.install_progress"

# --- Source Visual Engine ---
if [ -f "$SCRIPTS_DIR/00-utils.sh" ]; then
    source "$SCRIPTS_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

# --- Global Cleanup on Exit ---
cleanup() {
    rm -f "/tmp/shorin_install_user"
}
trap cleanup EXIT

# --- Global Trap (Restore Cursor on Exit) ---
cleanup_on_exit() {
    tput cnorm
}
trap cleanup_on_exit EXIT

# --- Environment ---
export DEBUG=${DEBUG:-0}
export CN_MIRROR=${CN_MIRROR:-0}

check_root
chmod +x "$SCRIPTS_DIR"/*.sh

# --- ASCII Banners ---
banner1() {
cat << "EOF"
   _____ __  ______  ____  _____   __
  / ___// / / / __ \/ __ \/  _/ | / /
  \__ \/ /_/ / / / / /_/ // //  |/ / 
 ___/ / __  / /_/ / _, _// // /|  /  
/____/_/ /_/\____/_/ |_/___/_/ |_/   
EOF
}

banner2() {
cat << "EOF"
  ██████  ██   ██  ██████  ███████ ██ ███    ██ 
  ██      ██   ██ ██    ██ ██   ██ ██ ██ ██  ██ 
  ███████ ███████ ██    ██ ██████  ██ ██ ██  ██ 
       ██ ██   ██ ██    ██ ██   ██ ██ ██  ██ ██ 
  ██████  ██   ██  ██████  ██   ██ ██ ██   ████ 
EOF
}
banner3() {
cat << "EOF"
   ______ __ __   ___   ____   ____  _   _ 
  / ___/|  |  | /   \ |    \ |    || \ | |
 (   \_ |  |  ||     ||  D  ) |  | |  \| |
  \__  ||  _  ||  O  ||    /  |  | |     |
  /  \ ||  |  ||     ||    \  |  | | |\  |
  \    ||  |  ||     ||  .  \ |  | | | \ |
   \___||__|__| \___/ |__|\_||____||_| \_|
EOF
}

show_banner() {
    clear
    local r=$(( $RANDOM % 3 ))
    echo -e "${H_CYAN}"
    case $r in
        0) banner1 ;;
        1) banner2 ;;
        2) banner3 ;;
    esac
    echo -e "${NC}"
    echo -e "${DIM}   :: Arch Linux Automation Protocol :: v1.1 ::${NC}"
    echo ""
}

# --- Desktop Selection Menu ---
select_desktop() {
    show_banner
    echo -e "${H_PURPLE}╭──────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${H_PURPLE}│${NC} ${BOLD}Choose your Desktop Environment:${NC}                             ${H_PURPLE}│${NC}"
    echo -e "${H_PURPLE}│${NC}                                                              ${H_PURPLE}│${NC}"
    echo -e "${H_PURPLE}│${NC}  ${H_CYAN}[1]${NC} Niri (Wayland Tiling Compositor)                       ${H_PURPLE}│${NC}"
    echo -e "${H_PURPLE}│${NC}  ${H_CYAN}[2]${NC} KDE Plasma 6 (Full Desktop Environment)                ${H_PURPLE}│${NC}"
    echo -e "${H_PURPLE}│${NC}                                                              ${H_PURPLE}│${NC}"
    echo -e "${H_PURPLE}╰──────────────────────────────────────────────────────────────╯${NC}"
    echo ""
    
    echo -e "   ${DIM}Waiting for input (Timeout: 2 mins)...${NC}"
    read -t 120 -p "$(echo -e "   ${H_YELLOW}Select [1/2]: ${NC}")" dt_choice
    
    if [ -z "$dt_choice" ]; then
        echo -e "\n${H_RED}Timeout or no selection.${NC}"
        exit 1
    fi
    
    case "$dt_choice" in
        1)
            export DESKTOP_ENV="niri"
            log "Selected: Niri"
            ;;
        2)
            export DESKTOP_ENV="kde"
            log "Selected: KDE Plasma"
            ;;
        *)
            error "Invalid selection."
            exit 1
            ;;
    esac
    sleep 1
}

sys_dashboard() {
    echo -e "${H_BLUE}╔════ SYSTEM DIAGNOSTICS ══════════════════════════════╗${NC}"
    echo -e "${H_BLUE}║${NC} ${BOLD}Kernel${NC}   : $(uname -r)"
    echo -e "${H_BLUE}║${NC} ${BOLD}User${NC}     : $(whoami)"
    echo -e "${H_BLUE}║${NC} ${BOLD}Desktop${NC}  : ${H_MAGENTA}${DESKTOP_ENV^^}${NC}"
    
    if [ "$CN_MIRROR" == "1" ]; then
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : ${H_YELLOW}CN Optimized (Manual)${NC}"
    elif [ "$DEBUG" == "1" ]; then
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : ${H_RED}DEBUG FORCE (CN Mode)${NC}"
    else
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : Global Default"
    fi
    
    if [ -f "$STATE_FILE" ]; then
        done_count=$(wc -l < "$STATE_FILE")
        echo -e "${H_BLUE}║${NC} ${BOLD}Progress${NC} : Resuming ($done_count steps recorded)"
    fi
    echo -e "${H_BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# --- Main Execution ---

select_desktop
clear
show_banner
sys_dashboard

# Dynamic Module List
BASE_MODULES=(
    "00-btrfs-init.sh"
    "01-base.sh"
    "02-musthave.sh"
    "03-user.sh"
)

if [ "$DESKTOP_ENV" == "niri" ]; then
    BASE_MODULES+=("04-niri-setup.sh")
elif [ "$DESKTOP_ENV" == "kde" ]; then
    BASE_MODULES+=("06-kdeplasma-setup.sh")
fi

BASE_MODULES+=("07-grub-theme.sh" "99-apps.sh")
MODULES=("${BASE_MODULES[@]}")

if [ ! -f "$STATE_FILE" ]; then touch "$STATE_FILE"; fi

TOTAL_STEPS=${#MODULES[@]}
CURRENT_STEP=0

log "Initializing installer sequence..."
sleep 0.5

# --- Reflector Mirror Update (State Aware) ---
section "Pre-Flight" "Mirrorlist Optimization"

# [MODIFIED] Check if already done
if grep -q "^REFLECTOR_DONE$" "$STATE_FILE"; then
    echo -e "   ${H_GREEN}✔${NC} Mirrorlist previously optimized."
    echo -e "   ${DIM}   Skipping Reflector steps (Resume Mode)...${NC}"
else
    # --- Start Reflector Logic ---
    log "Checking Reflector..."
    exe pacman -Sy --noconfirm --needed reflector

    CURRENT_TZ=$(readlink -f /etc/localtime)
    REFLECTOR_ARGS="-a 24 -f 10 --sort score --save /etc/pacman.d/mirrorlist --verbose"

    if [[ "$CURRENT_TZ" == *"Shanghai"* ]]; then
        echo ""
        echo -e "${H_YELLOW}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${H_YELLOW}║  DETECTED TIMEZONE: Asia/Shanghai                                ║${NC}"
        echo -e "${H_YELLOW}║  Refreshing mirrors in China can be slow.                        ║${NC}"
        echo -e "${H_YELLOW}║  Do you want to force refresh mirrors with Reflector?            ║${NC}"
        echo -e "${H_YELLOW}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -t 60 -p "$(echo -e "   ${H_CYAN}Run Reflector? [y/N] (Default No in 60s): ${NC}")" choice
        if [ $? -ne 0 ]; then echo ""; fi
        choice=${choice:-N}
        
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            log "Running Reflector for China..."
            if exe reflector $REFLECTOR_ARGS -c China; then
                success "Mirrors updated."
            else
                warn "Reflector failed. Continuing with existing mirrors."
            fi
        else
            log "Skipping mirror refresh."
        fi
    else
        log "Detecting location for optimization..."
        COUNTRY_CODE=$(curl -s --max-time 2 https://ipinfo.io/country)
        
        if [ -n "$COUNTRY_CODE" ]; then
            info_kv "Country" "$COUNTRY_CODE" "(Auto-detected)"
            log "Running Reflector for $COUNTRY_CODE..."
            if ! exe reflector $REFLECTOR_ARGS -c "$COUNTRY_CODE"; then
                warn "Country specific refresh failed. Trying global speed test..."
                exe reflector $REFLECTOR_ARGS
            fi
        else
            warn "Could not detect country. Running global speed test..."
            exe reflector $REFLECTOR_ARGS
        fi
        success "Mirrorlist optimized."
    fi
    # --- End Reflector Logic ---

    # [MODIFIED] Record success so we don't ask again
    echo "REFLECTOR_DONE" >> "$STATE_FILE"
fi


# --- Global Update ---
section "Pre-Flight" "System Synchronization"
log "Ensuring system is up-to-date..."

if exe pacman -Syu --noconfirm; then
    success "System Updated."
else
    error "System update failed. Check your network."
    exit 1
fi

# --- Module Loop ---
for module in "${MODULES[@]}"; do
    CURRENT_STEP=$((CURRENT_STEP + 1))
    script_path="$SCRIPTS_DIR/$module"
    
    if [ ! -f "$script_path" ]; then
        error "Module not found: $module"
        continue
    fi

    # Checkpoint Logic: Auto-skip if in state file
    if grep -q "^${module}$" "$STATE_FILE"; then
        echo -e "   ${H_GREEN}✔${NC} Module ${BOLD}${module}${NC} already completed."
        echo -e "   ${DIM}   Skipping... (Delete .install_progress to force run)${NC}"
        continue
    fi

    section "Module ${CURRENT_STEP}/${TOTAL_STEPS}" "$module"

    bash "$script_path"
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        # Only record success
        echo "$module" >> "$STATE_FILE"
        success "Module $module completed."
    elif [ $exit_code -eq 130 ]; then
        echo ""
        warn "Script interrupted by user (Ctrl+C)."
        log "Exiting without rollback. You can resume later."
        exit 130
    else
        # Failure logic: do NOT write to STATE_FILE
        write_log "FATAL" "Module $module failed with exit code $exit_code"
        error "Module execution failed."
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# Final Cleanup
# ------------------------------------------------------------------------------
section "Completion" "System Cleanup"

# --- 1. Snapshot Cleanup Logic ---
clean_intermediate_snapshots() {
    local config_name="$1"
    local marker_name="Before Shorin Setup"
    
    if ! snapper -c "$config_name" list &>/dev/null; then
        return
    fi

    log "Scanning junk snapshots in: $config_name..."

    local start_id
    start_id=$(snapper -c "$config_name" list --columns number,description | grep "$marker_name" | awk '{print $1}' | tail -n 1)

    if [ -z "$start_id" ]; then
        warn "Marker '$marker_name' not found in '$config_name'. Skipping."
        return
    fi

    local snapshots_to_delete=()
    while read -r line; do
        local id
        local type
        
        id=$(echo "$line" | awk '{print $1}')
        type=$(echo "$line" | awk '{print $3}')

        if [[ "$id" =~ ^[0-9]+$ ]]; then
            if [ "$id" -gt "$start_id" ]; then
                if [[ "$type" == "pre" || "$type" == "post" || "$type" == "single" ]]; then
                    snapshots_to_delete+=("$id")
                fi
            fi
        fi
    done < <(snapper -c "$config_name" list --columns number,type)

    if [ ${#snapshots_to_delete[@]} -gt 0 ]; then
        log "Deleting ${#snapshots_to_delete[@]} snapshots in '$config_name'..."
        if exe snapper -c "$config_name" delete "${snapshots_to_delete[@]}"; then
            success "Cleaned $config_name."
        fi
    else
        log "No junk snapshots found in '$config_name'."
    fi
}

# --- 2. Execute Cleanup ---
log "Cleaning Pacman/Yay cache..."
exe pacman -Sc --noconfirm

clean_intermediate_snapshots "root"
clean_intermediate_snapshots "home"

# --- 3. Remove Installer Files ---
if [ -d "/root/shorin-arch-setup" ]; then
    log "Removing installer from /root..."
    cd /
    rm -rfv /root/shorin-arch-setup
else
    log "Repo cleanup skipped (not in /root/shorin-arch-setup)."
    log "If you cloned this manually, please remove the folder yourself."
fi

# --- 4. Final GRUB Update ---
log "Regenerating final GRUB configuration..."
exe grub-mkconfig -o /boot/grub/grub.cfg

# --- Completion ---
clear
show_banner
echo -e "${H_GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${H_GREEN}║             INSTALLATION  COMPLETE                   ║${NC}"
echo -e "${H_GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

if [ -f "$STATE_FILE" ]; then rm "$STATE_FILE"; fi

log "Archiving log..."
if [ -f "/tmp/shorin_install_user" ]; then
    FINAL_USER=$(cat /tmp/shorin_install_user)
else
    FINAL_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
fi

if [ -n "$FINAL_USER" ]; then
    FINAL_DOCS="/home/$FINAL_USER/Documents"
    mkdir -p "$FINAL_DOCS"
    cp "$TEMP_LOG_FILE" "$FINAL_DOCS/log-shorin-arch-setup.txt"
    chown -R "$FINAL_USER:$FINAL_USER" "$FINAL_DOCS"
    echo -e "   ${H_BLUE}●${NC} Log Saved     : ${BOLD}$FINAL_DOCS/log-shorin-arch-setup.txt${NC}"
fi

# --- Reboot Countdown ---
echo ""
echo -e "${H_YELLOW}>>> System requires a REBOOT.${NC}"

while read -r -t 0; do read -r; done

for i in {10..1}; do
    echo -ne "\r   ${DIM}Auto-rebooting in ${i}s... (Press 'n' to cancel)${NC}"
    
    read -t 1 -n 1 input
    if [ $? -eq 0 ]; then
        if [[ "$input" == "n" || "$input" == "N" ]]; then
            echo -e "\n\n   ${H_BLUE}>>> Reboot cancelled.${NC}"
            exit 0
        else
            break
        fi
    fi
done

echo -e "\n\n   ${H_GREEN}>>> Rebooting...${NC}"
systemctl reboot