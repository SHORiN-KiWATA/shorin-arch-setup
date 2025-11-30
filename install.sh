#!/bin/bash

# ==============================================================================
# shorin-arch-setup Installer
# ==============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"

source "$SCRIPTS_DIR/00-utils.sh"

check_root

# Make scripts executable
chmod +x "$SCRIPTS_DIR"/*.sh

clear
echo -e "${BLUE}"
cat << "EOF"
   _____ __  ______  ____  _____   __
  / ___// / / / __ \/ __ \/  _/ | / /
  \__ \/ /_/ / / / / /_/ // //  |/ / 
 ___/ / __  / /_/ / _, _// // /|  /  
/____/_/ /_/\____/_/ |_/___/_/ |_/   
                                     
   Arch Linux Setup Script by Shorin
EOF
echo -e "${NC}"
log "Welcome to the automated setup script."
log "Installation logs will be output to this console."
echo "----------------------------------------------------"

MODULES=(
    "01-base.sh"
    "02-musthave.sh"
    "03-user.sh"
    "04-niri-setup.sh"
)

for module in "${MODULES[@]}"; do
    script_path="$SCRIPTS_DIR/$module"
    
    if [ -f "$script_path" ]; then
        log "Executing module: $module"
        bash "$script_path"
        
        if [ $? -ne 0 ]; then
            error "Module $module failed. Installation aborted!"
            exit 1
        fi
    else
        warn "Module not found: $module"
    fi
done

echo "----------------------------------------------------"
success "All selected modules executed successfully!"