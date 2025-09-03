#!/bin/bash

# Script to automatically enable container support for Proxmox storage
# This script attempts to fix the "storage does not support container directories" error

function info() {
    echo -e "\e[36m[INFO] $1\e[39m"
}

function warn() {
    echo -e "\e[93m[WARNING] $1\e[39m"
}

function error() {
    echo -e "\e[91m[ERROR] $1\e[39m"
}

function fatal() {
    echo -e "\e[91m[FATAL] $1\e[39m"
    exit 1
}

echo "======================================"
echo "Proxmox Storage Container Support Fix"
echo "======================================"
echo

# Check if we're in a Proxmox environment
if ! command -v pvesm >/dev/null 2>&1; then
    fatal "This script must be run on a Proxmox node (pvesm command not found)"
fi

if ! command -v pvesh >/dev/null 2>&1; then
    fatal "This script must be run on a Proxmox node (pvesh command not found)"
fi

# Get the storage name from command line or prompt user
STORAGE_NAME="$1"

if [ -z "$STORAGE_NAME" ]; then
    echo "Available storages:"
    pvesm status 2>/dev/null || fatal "Could not get storage status"
    echo
    read -p "Enter storage name to configure for containers: " STORAGE_NAME
fi

if [ -z "$STORAGE_NAME" ]; then
    fatal "No storage name provided"
fi

# Check if storage exists
STORAGE_INFO=$(pvesm status 2>/dev/null | grep "^$STORAGE_NAME[[:space:]]")
if [ -z "$STORAGE_INFO" ]; then
    error "Storage '$STORAGE_NAME' not found"
    echo "Available storages:"
    pvesm status 2>/dev/null
    exit 1
fi

info "Found storage: $STORAGE_NAME"
info "Storage details: $STORAGE_INFO"

# Check current content types
CURRENT_CONTENT=$(echo "$STORAGE_INFO" | grep -o 'content: [^[:space:]]*' | cut -d' ' -f2 || echo "none")
info "Current content types: $CURRENT_CONTENT"

# Check if container support is already enabled
if echo "$STORAGE_INFO" | grep -q "rootdir\|vztmpl"; then
    info "✅ Container support is already enabled for storage '$STORAGE_NAME'"
    echo "Content types include: $(echo "$STORAGE_INFO" | grep -o 'rootdir\|vztmpl' | tr '\n' ',' | sed 's/,$//')"
    exit 0
fi

# Attempt to enable container support
info "Attempting to enable container support for storage '$STORAGE_NAME'..."

# Get current storage configuration
STORAGE_CONFIG=$(pvesh get /storage/$STORAGE_NAME --output-format json 2>/dev/null)
if [ $? -ne 0 ]; then
    error "Could not retrieve configuration for storage '$STORAGE_NAME'"
    error "You may need to enable container support manually in the Proxmox web interface:"
    echo "  1. Go to Datacenter > Storage"
    echo "  2. Click on storage: $STORAGE_NAME"
    echo "  3. In the 'Content' section, check 'Container' checkbox"
    echo "  4. Click 'OK' to save"
    exit 1
fi

# Try to add container content types
info "Adding container content types (rootdir,vztmpl) to storage '$STORAGE_NAME'..."

# Build new content string
NEW_CONTENT="$CURRENT_CONTENT"
if [[ "$NEW_CONTENT" != *"rootdir"* ]]; then
    if [ "$NEW_CONTENT" = "none" ] || [ -z "$NEW_CONTENT" ]; then
        NEW_CONTENT="rootdir"
    else
        NEW_CONTENT="$NEW_CONTENT,rootdir"
    fi
fi

if [[ "$NEW_CONTENT" != *"vztmpl"* ]]; then
    NEW_CONTENT="$NEW_CONTENT,vztmpl"
fi

# Apply the configuration change
info "Setting content types to: $NEW_CONTENT"
if pvesm set "$STORAGE_NAME" --content "$NEW_CONTENT" 2>/dev/null; then
    info "✅ Successfully enabled container support for storage '$STORAGE_NAME'"
    
    # Verify the change
    sleep 2
    UPDATED_INFO=$(pvesm status 2>/dev/null | grep "^$STORAGE_NAME[[:space:]]")
    if echo "$UPDATED_INFO" | grep -q "rootdir\|vztmpl"; then
        info "✅ Verification successful - container support is now enabled"
        info "Updated storage details: $UPDATED_INFO"
        echo
        info "You can now run the setup script again - it should work without the storage error"
    else
        warn "Configuration may not have been applied correctly"
        warn "Please check the Proxmox web interface to verify container support is enabled"
    fi
else
    error "Failed to enable container support automatically"
    error "You may need to enable it manually in the Proxmox web interface:"
    echo "  1. Go to Datacenter > Storage"
    echo "  2. Click on storage: $STORAGE_NAME"
    echo "  3. In the 'Content' section, check 'Container' checkbox"
    echo "  4. Click 'OK' to save"
    echo
    error "Alternatively, try running this command manually:"
    echo "  pvesm set $STORAGE_NAME --content $NEW_CONTENT"
    exit 1
fi

echo
echo "======================================"
echo "Storage configuration completed!"
echo "======================================"