#!/bin/bash

# ==============================================================================
# Shorin Arch Setup - Main Installer (v5.2 - Dual Rollback)
# ==============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
STATE_FILE="$BASE_DIR/.install_progress"

if [ -f "$SCRIPTS_DIR/00-utils.sh" ]; then
    source "$SCRIPTS_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

# --- Global Cleanup on Exit ---
cleanup() {
    # This function is called on EXIT.
    # Add any other temporary files here if needed.
    rm -f "/tmp/shorin_install_user"
}
trap cleanup EXIT

# --- Environment Propagation ---
export DEBUG=${DEBUG:-0}
export CN_MIRROR=${CN_MIRROR:-0}

check_root
chmod +x "$SCRIPTS_DIR"/*.sh

# --- Helper: Emergency Rollback (Updated) ---
trigger_emergency_recovery() {
    local err_code=$1
    
    echo ""
    echo -e "${H_RED}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${H_RED}║  CRITICAL FAILURE DETECTED (Exit Code: $err_code)                     ║${NC}"
    echo -e "${H_RED}║  The installation script encountered an unrecoverable error.     ║${NC}"
    echo -e "${H_RED}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if ! command -v snapper &> /dev/null; then
        warn "Snapper not found. Cannot perform rollback."
        return
    fi

    # 1. Identify Root Snapshot
    local ROOT_SNAP_ID=$(snapper -c root list --columns number,description | grep "Before Shorin Setup" | tail -n 1 | awk '{print $1}')

    # 2. Identify Home Snapshot (If exists)
    local HOME_SNAP_ID=""
    if snapper list-configs | grep -q "^home "; then
        HOME_SNAP_ID=$(snapper -c home list --columns number,description | grep "Before Shorin Setup" | tail -n 1 | awk '{print $1}')
    fi

    if [ -z "$ROOT_SNAP_ID" ]; then
        warn "Initial safety snapshot 'Before Shorin Setup' not found."
        return
    fi

    echo -e "   ${H_YELLOW}Safety snapshot found:${NC}"
    echo -e "     - Root Config ID: ${BOLD}$ROOT_SNAP_ID${NC}"
    if [ -n "$HOME_SNAP_ID" ]; then
        echo -e "     - Home Config ID: ${BOLD}$HOME_SNAP_ID${NC}"
    fi
    
    echo -e "\n   You can revert ALL system changes (Filesystem & User Data) right now."
    echo ""
    echo -e "   ${BOLD}Manual Recovery Commands:${NC}"
    echo -e "   ${H_CYAN}sudo snapper -c root undochange $ROOT_SNAP_ID..0${NC}"
    if [ -n "$HOME_SNAP_ID" ]; then
        echo -e "   ${H_CYAN}sudo snapper -c home undochange $HOME_SNAP_ID..0${NC}"
    fi
    echo -e "   ${H_CYAN}reboot${NC}"
    echo ""

    # 3. Ask User
    while read -r -t 0; do read -r; done
    
    read -p "$(echo -e "   ${H_RED}${BOLD}ROLLBACK system changes and REBOOT now? [y/N]: ${NC}")" choice
    
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo ""
        log "Performing emergency rollback..."
        
        # Rollback Root
        log "Reverting ROOT filesystem..."
        if exe snapper -c root undochange "$ROOT_SNAP_ID..0"; then
            success "Root reverted."
        else
            error "Root rollback failed."
        fi

        # Rollback Home
        if [ -n "$HOME_SNAP_ID" ]; then
            log "Reverting HOME filesystem..."
            if exe snapper -c home undochange "$HOME_SNAP_ID..0"; then
                success "Home reverted."
            else
                error "Home rollback failed."
            fi
        fi
            
        # Clean up state file so next run starts fresh
        rm -f "$STATE_FILE"
        
        echo -e "${H_GREEN}>>> Rebooting to apply rollback...${NC}"
        sleep 2
        systemctl reboot
    else
        log "Rollback skipped. You are in a partially installed state."
        echo -e "   Please fix the issue and re-run ${BOLD}./install.sh${NC}"
    fi
}

# --- Banner Functions ---
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
  ██████  ██   ██  ██████  ██████  ██ ███    ██ 
  ██      ██   ██ ██    ██ ██████  ██ ██ ██  ██ 
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
    echo -e "${DIM}   :: Arch Linux Automation Protocol :: v5.2 ::${NC}"
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
        echo -e "${H_BLUE}║${NC} ${BOLD}Progress${NC} : Resuming ($done_count modules done)"
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
    "00-btrfs-init.sh"  # Critical: Must be first to create snapshot
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

# --- Pacman Lock Fix ---
if [ -f /var/lib/pacman/db.lck ]; then
    echo -e "${H_YELLOW}   [!] Pacman lock file detected. Removing it...${NC}"
    rm /var/lib/pacman/db.lck
fi

# --- Reflector ---
section "Pre-Flight" "Mirrorlist Optimization"
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

    section "Module ${CURRENT_STEP}/${TOTAL_STEPS}" "$module"

    if grep -q "^${module}$" "$STATE_FILE"; then
        echo -e "   ${H_GREEN}✔${NC} Module previously completed."
        read -p "$(echo -e "   ${H_YELLOW}Skip this module? [Y/n] ${NC}")" skip_choice
        skip_choice=${skip_choice:-Y}
        if [[ "$skip_choice" =~ ^[Yy]$ ]]; then log "Skipping..."; continue; else log "Force re-running..."; sed -i "/^${module}$/d" "$STATE_FILE"; fi
    fi

    bash "$script_path"
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "$module" >> "$STATE_FILE"
    elif [ $exit_code -eq 130 ]; then
        echo ""
        warn "Script interrupted by user (Ctrl+C)."
        log "Exiting without rollback. You can resume later."
        exit 130
    else
        write_log "FATAL" "Module $module failed with exit code $exit_code"
        trigger_emergency_recovery $exit_code
        exit 1
    fi
done

# --- Completion ---
clear
show_banner
echo -e "${H_GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${H_GREEN}║             INSTALLATION  COMPLETE                   ║${NC}"
echo -e "${H_GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

if [ -f "$STATE_FILE" ]; then rm "$STATE_FILE"; fi

log "Archiving log..."
# Try to read from temp file first, fallback to detection
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

echo ""
echo -e "${H_YELLOW}>>> System requires a REBOOT.${NC}"

# Clear input buffer
while read -r -t 0; do read -r; done

for i in {10..1}; do
    echo -ne "\r   ${DIM}Auto-rebooting in ${i}s... (Press 'n' to cancel)${NC}"
    read -t 1 -N 1 input
    if [[ "$input" == "n" || "$input" == "N" ]]; then
        echo -e "\n\n   ${H_BLUE}>>> Reboot cancelled.${NC}"
        exit 0
    fi
done
echo -e "\n\n   ${H_GREEN}>>> Rebooting...${NC}"
systemctl reboot