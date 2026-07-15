#!/bin/bash

# ==============================================================================
# 01b-shorin-arch.sh - Configure Shorin Arch Repository
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log "Starting: Shorin Arch Repository configuration..."

KEY_FPR="8ED9ABE61CDBAABAC4B6A694C9218E60C13B4BA8"
KEY_FILE="$PARENT_DIR/resources/shorin-arch/shorin-arch.asc"

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
if [ ! -r "$KEY_FILE" ]; then
    error "Bundled GPG public key not found: $KEY_FILE"
    exit 1
fi

KEY_FILE_FPR=$(gpg --batch --with-colons --show-keys "$KEY_FILE" 2>/dev/null \
| awk -F: '$1 == "fpr" { print $10; exit }')

if [ "$KEY_FILE_FPR" != "$KEY_FPR" ]; then
    error "Bundled GPG public key fingerprint mismatch."
    error "Expected: $KEY_FPR"
    error "Found: ${KEY_FILE_FPR:-unreadable key}"
    exit 1
fi

if pacman-key --list-keys "$KEY_FPR" >/dev/null 2>&1; then
    success "GPG key already present."
else
    log "Importing bundled GPG key from $KEY_FILE..."
    if ! pacman-key --add "$KEY_FILE" >/dev/null 2>&1 \
    || ! pacman-key --list-keys "$KEY_FPR" >/dev/null 2>&1; then
        error "Failed to import the bundled GPG public key."
        exit 1
    fi
    success "Bundled GPG key imported."
fi

log "Locally signing GPG key..."
if pacman-key --lsign-key "$KEY_FPR" >/dev/null 2>&1; then
    success "GPG key locally signed and trusted."
else
    error "Failed to locally sign GPG key: $KEY_FPR"
    exit 1
fi

# ------------------------------------------------------------------------------
# 3. Refresh database
# ------------------------------------------------------------------------------
exe pacman -Syu --noconfirm
success "Shorin Arch repository configured."

log "Module 01b completed."
