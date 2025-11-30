#!/bin/bash

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log ">>> Starting Phase 3: User Creation & Configuration"

# ------------------------------------------------------------------------------
# 1. Input Username
# ------------------------------------------------------------------------------
log "Step 1/4: Setup Username"

while true; do
    read -p "Please enter the username to configure: " MY_USERNAME
    if [[ -z "$MY_USERNAME" ]]; then
        warn "Username cannot be empty."
    elif id "$MY_USERNAME" &>/dev/null; then
        warn "User '$MY_USERNAME' already exists."
        read -p "Do you want to use this existing user? (y/n): " USE_EXISTING
        if [[ "$USE_EXISTING" == "y" || "$USE_EXISTING" == "Y" ]]; then
            break
        fi
    else
        # New user, break to proceed
        break
    fi
done

# ------------------------------------------------------------------------------
# 2. Create or Update User
# ------------------------------------------------------------------------------
log "Step 2/4: Configuring user '$MY_USERNAME'..."

if id "$MY_USERNAME" &>/dev/null; then
    log "-> User '$MY_USERNAME' exists. Checking groups..."
    
    # Ensure existing user is in the wheel group
    if groups "$MY_USERNAME" | grep -q "\bwheel\b"; then
        log "-> User is already in 'wheel' group."
    else
        log "-> Adding user '$MY_USERNAME' to 'wheel' group for sudo access..."
        usermod -aG wheel "$MY_USERNAME"
        success "User added to wheel group."
    fi
    
    log "-> Skipping password reset for existing user."
else
    # Create new user
    log "-> Creating new user '$MY_USERNAME'..."
    useradd -m -G wheel "$MY_USERNAME"
    success "User '$MY_USERNAME' created."
    
    log "-> Setting password for '$MY_USERNAME'..."
    passwd "$MY_USERNAME"
fi

# ------------------------------------------------------------------------------
# 3. Configure Sudoers
# ------------------------------------------------------------------------------
log "Step 3/4: Configuring Sudo privileges (Wheel group)..."

# Ensure %wheel group has sudo access
if grep -q "^# %wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    success "Enabled sudo access for %wheel group."
elif grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    success "Sudo access for %wheel group is already enabled."
else
    log "-> Could not find exact commented line. Appending rule to /etc/sudoers..."
    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
    success "Appended wheel config to /etc/sudoers."
fi

# ------------------------------------------------------------------------------
# 4. Generate User Directories (xdg-user-dirs)
# ------------------------------------------------------------------------------
log "Step 4/4: Generating user directories (Downloads, Music, etc.)..."

# Use runuser to execute as the target user
if runuser -u "$MY_USERNAME" -- xdg-user-dirs-update; then
    success "Directories generated for '$MY_USERNAME'."
else
    # This might fail if the user is not logged in or DBus session is missing, 
    # but it's worth a try. If it fails, xdg-user-dirs will just run on next login.
    warn "Could not generate directories now (maybe no session). They will be created on first login."
fi

log ">>> Phase 3 completed."