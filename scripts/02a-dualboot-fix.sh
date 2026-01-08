#!/bin/bash

# ==============================================================================
# Script: 02a-dualboot-fix.sh
# Purpose: Auto-configure for Windows dual-boot (OS-Prober only).
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

# --- GRUB Installation Check ---
if ! command -v grub-mkconfig &>/dev/null || [ ! -f "/etc/default/grub" ]; then
    warn "GRUB is not detected. Skipping dual-boot configuration."
    exit 0
fi

# --- Helper Functions ---

# Sets a GRUB key-value pair.
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

# --- Main Script ---

section "Phase 2A" "Dual-Boot Configuration (Windows)"

# ------------------------------------------------------------------------------
# 1. Detect Windows
# ------------------------------------------------------------------------------
section "Step 1/2" "System Analysis"

log "Installing dual-boot detection tools (os-prober, exfat-utils)..."
exe pacman -S --noconfirm --needed os-prober exfat-utils

log "Scanning for Windows installation..."
WINDOWS_DETECTED=$(os-prober | grep -qi "windows" && echo "true" || echo "false")

if [ "$WINDOWS_DETECTED" != "true" ]; then
    log "No Windows installation detected by os-prober."
    log "Skipping dual-boot specific configurations."
    log "Module 02a completed (Skipped)."
    exit 0
fi

success "Windows installation detected."

# --- Check if already configured ---
OS_PROBER_CONFIGURED=$(grep -q -E '^\s*GRUB_DISABLE_OS_PROBER\s*=\s*(false|"false")' /etc/default/grub && echo "true" || echo "false")

if [ "$OS_PROBER_CONFIGURED" == "true" ]; then
    log "Dual-boot settings seem to be already configured."
    echo ""
    echo -e "   ${H_YELLOW}>>> It looks like your dual-boot is already set up.${NC}"
    echo ""
fi

# ------------------------------------------------------------------------------
# 2. Configure GRUB for Dual-Boot
# ------------------------------------------------------------------------------
section "Step 2/2" "Enabling OS Prober"

log "Enabling OS prober to detect Windows..."
set_grub_value "GRUB_DISABLE_OS_PROBER" "false"

success "Dual-boot settings updated."

log "Regenerating GRUB configuration..."
if exe grub-mkconfig -o /boot/grub/grub.cfg; then
    success "GRUB configuration regenerated successfully."
else
    error "Failed to regenerate GRUB configuration."
fi

log "Module 02a completed."