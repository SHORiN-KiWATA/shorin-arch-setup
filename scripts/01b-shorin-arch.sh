#!/bin/bash

# ==============================================================================
# 01b-shorin-arch.sh - Configure Shorin Arch Repository
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log "Starting: Shorin Arch Repository configuration..."

KEY_FPR="8ED9ABE61CDBAABAC4B6A694C9218E60C13B4BA8"
GPGSETUP_URL="https://repo.shorin.xyz/archlinux/gpgsetup"

# ------------------------------------------------------------------------------
# 1. Add repository to pacman.conf
# ------------------------------------------------------------------------------
if grep -q "\[shorin-arch\]" /etc/pacman.conf; then
    success "shorin-arch repository already exists."
else
    log "Adding shorin-arch repository to pacman.conf..."
    echo "" >> /etc/pacman.conf
    cat <<EOT >> /etc/pacman.conf
[shorin-arch]
Server = https://repo.shorin.xyz/archlinux/\$arch
EOT
    success "Repository added."
fi

# ------------------------------------------------------------------------------
# 2. Import and sign GPG key
# ------------------------------------------------------------------------------
if pacman-key --list-keys "$KEY_FPR" >/dev/null 2>&1; then
    success "GPG key already present."
else
    log "Importing GPG key from $GPGSETUP_URL..."
    if curl -L --fail --silent --show-error "$GPGSETUP_URL" | bash && pacman-key --list-keys "$KEY_FPR" >/dev/null 2>&1; then
        pacman-key --lsign-key "$KEY_FPR" >/dev/null 2>&1
        success "GPG key imported via gpgsetup and signed."
    else
        warn "gpgsetup failed, trying keyserver fallback..."
        if pacman-key --keyserver hkp://keys.openpgp.org --recv-keys "$KEY_FPR" 2>/dev/null; then
            pacman-key --lsign-key "$KEY_FPR" >/dev/null 2>&1
            success "GPG key received from keyserver and signed."
        else
            warn "Both methods failed. You can manually import:"
            warn "  curl -L $GPGSETUP_URL | bash"
            warn "  sudo pacman-key --keyserver hkp://keys.openpgp.org --recv-keys $KEY_FPR"
            warn "  sudo pacman-key --lsign-key $KEY_FPR"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 3. Refresh database
# ------------------------------------------------------------------------------
exe pacman -Syu --noconfirm
success "Shorin Arch repository configured."

log "Module 01b completed."
