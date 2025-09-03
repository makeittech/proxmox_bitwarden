#!/bin/bash

# Test script for storage selection function
# This helps debug the storage selection issue

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Message functions
msg_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
msg_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
msg_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
msg_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running on Proxmox
check_proxmox() {
    if ! command -v pvesm >/dev/null 2>&1; then
        msg_error "This script must be run on a Proxmox VE host"
        msg_error "The pvesm command is not available"
        msg_info "Please run this test on your Proxmox host"
        exit 1
    fi
    
    if ! command -v pct >/dev/null 2>&1; then
        msg_error "This script must be run on a Proxmox VE host"
        msg_error "The pct command is not available"
        msg_info "Please run this test on your Proxmox host"
        exit 1
    fi
    
    msg_ok "Running on Proxmox VE host"
}

# Storage selection function (copied from setup.sh)
select_storage() {
    local content_type="$1"
    local content_label="$2"
    
    msg_info "Selecting storage for $content_label..."
    
    # Get available storages for the content type
    local -a available_storages
    mapfile -t available_storages < <(pvesm status -content "$content_type" 2>/dev/null | awk 'NR>1 {print $1}' | grep -v '^$')
    
    if [ ${#available_storages[@]} -eq 0 ]; then
        msg_error "No storage found for content type '$content_type'"
        return 1
    fi
    
    # Debug: show available storages
    msg_info "Available storages for $content_label: ${available_storages[*]}"
    
    if [ ${#available_storages[@]} -eq 1 ]; then
        local selected_storage="${available_storages[0]}"
        msg_info "Auto-selecting single storage: $selected_storage"
        echo "$selected_storage"
        return 0
    fi
    
    # Multiple storages - let user choose
    echo "Available storages for $content_label:" >&2
    PS3="Select storage for $content_label: "
    select storage in "${available_storages[@]}"; do
        if [[ -n "$storage" ]]; then
            echo "$storage"
            return 0
        fi
        echo "Invalid selection. Please try again." >&2
    done
}

# Test the function
echo "=== Testing Storage Selection ==="

# Check if we're on Proxmox
check_proxmox

# Test template storage selection
echo -e "\n--- Testing Template Storage Selection ---"
TEMPLATE_STORAGE=$(select_storage "vztmpl" "templates")
if [[ $? -eq 0 ]]; then
    msg_ok "Template storage selection successful"
    msg_info "Raw output: '$TEMPLATE_STORAGE'"
    
    # Clean up storage name
    CLEAN_TEMPLATE_STORAGE=$(echo "$TEMPLATE_STORAGE" | tr -d '\n\r' | xargs)
    msg_info "Cleaned template storage: '$CLEAN_TEMPLATE_STORAGE'"
    
    # Test if it's a valid storage name
    if [[ "$CLEAN_TEMPLATE_STORAGE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        msg_ok "Template storage name is valid"
    else
        msg_error "Template storage name contains invalid characters: '$CLEAN_TEMPLATE_STORAGE'"
    fi
else
    msg_error "Template storage selection failed"
fi

# Test container storage selection
echo -e "\n--- Testing Container Storage Selection ---"
CONTAINER_STORAGE=$(select_storage "rootdir" "containers")
if [[ $? -eq 0 ]]; then
    msg_ok "Container storage selection successful"
    msg_info "Raw output: '$CONTAINER_STORAGE'"
    
    # Clean up storage name
    CLEAN_CONTAINER_STORAGE=$(echo "$CONTAINER_STORAGE" | tr -d '\n\r' | xargs)
    msg_info "Cleaned container storage: '$CLEAN_CONTAINER_STORAGE'"
    
    # Test if it's a valid storage name
    if [[ "$CLEAN_CONTAINER_STORAGE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        msg_ok "Container storage name is valid"
    else
        msg_error "Container storage name contains invalid characters: '$CLEAN_CONTAINER_STORAGE'"
    fi
else
    msg_error "Container storage selection failed"
fi

echo -e "\n=== Test Complete ==="