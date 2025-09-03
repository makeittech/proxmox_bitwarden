#!/bin/bash

# Test script for storage discovery logic
# This simulates the storage discovery part of the main setup script

function info() {
    echo -e "\e[36m[INFO] $1\e[39m"
}

function warn() {
    echo -e "\e[93m[WARNING] $1\e[39m"
}

function error() {
    echo -e "\e[91m[ERROR] $1\e[39m"
}

function configure_storage_for_containers() {
    local storage_name="$1"
    echo -e "\n\e[36m=== Configuring Storage for Containers ===\e[39m"
    echo "To enable container support for storage '$storage_name':"
    echo ""
    echo "1. Open Proxmox web interface in your browser"
    echo "2. Navigate to: Datacenter > Storage"
    echo "3. Click on storage: $storage_name"
    echo "4. In the 'Content' section, check the 'Container' checkbox"
    echo "5. Click 'OK' to save changes"
    echo "6. Run this script again"
    echo ""
    echo "Alternative: Use command line (if you have access):"
    echo "pvesm set $storage_name --content rootdir,vztmpl"
    echo -e "\e[36m============================================\e[39m\n"
}

echo "=== Storage Discovery Test ==="

# Check if we're in a Proxmox environment
if ! command -v pvesm >/dev/null 2>&1; then
    error "This script must be run in a Proxmox environment"
    error "pvesm command not found"
    exit 1
fi

# Discover available storage locations
info "Discovering available storage locations..."

# Debug: Show all available storages first
info "All available storages:"
pvesm status 2>/dev/null || warn "Could not get storage status"

# Get all available storages first
STORAGE_LIST=($(pvesm status 2>/dev/null | awk 'NR>1 {print $1}' | grep -v '^$'))

# If no storages found, try alternative methods
if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
    warn "No storages found with pvesm status, trying alternative methods..."
    # Try getting storages with container content type
    STORAGE_LIST=($(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 {print $1}' | grep -v '^$'))
    
    if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
        # Try getting storages with vztmpl content type
        STORAGE_LIST=($(pvesm status -content vztmpl 2>/dev/null | awk 'NR>1 {print $1}' | grep -v '^$'))
    fi
fi

info "Found ${#STORAGE_LIST[@]} storage(s): ${STORAGE_LIST[*]}"

# Filter out storages that are not accessible or don't support containers
ACCESSIBLE_STORAGES=()
info "Checking storage accessibility and container support..."

for storage in "${STORAGE_LIST[@]}"; do
    info "Checking storage: $storage"
    
    # Check if storage is accessible and get details
    STORAGE_INFO=$(pvesm status 2>/dev/null | grep "^$storage[[:space:]]")
    if [ -z "$STORAGE_INFO" ]; then
        warn "Storage $storage is not accessible"
        continue
    fi
    info "Storage $storage details: $STORAGE_INFO"
    
    # Check if storage supports containers (has rootdir or vztmpl content type)
    if echo "$STORAGE_INFO" | grep -q "rootdir\|vztmpl"; then
        info "Storage $storage supports containers"
        ACCESSIBLE_STORAGES+=("$storage")
    else
        # Storage exists but might not have container content type configured
        # This is often a configuration issue, not an accessibility issue
        warn "Storage $storage exists but container content type not configured"
        warn "This storage can be configured for containers in Proxmox web interface"
        # Still add it as potentially usable - the user can configure it
        ACCESSIBLE_STORAGES+=("$storage")
    fi
done

STORAGE_LIST=("${ACCESSIBLE_STORAGES[@]}")

if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
    error "No accessible storage locations found. Available storages:"
    pvesm status 2>/dev/null || error "Could not get storage status"
    
    # Try common storage names as fallback
    info "Trying common storage names as fallback..."
    COMMON_STORAGES=("local" "local-lvm" "local-zfs" "pve" "storage")
    
    for common_storage in "${COMMON_STORAGES[@]}"; do
        STORAGE_INFO=$(pvesm status 2>/dev/null | grep "^$common_storage[[:space:]]")
        if [ -n "$STORAGE_INFO" ]; then
            info "Found storage: $common_storage - $STORAGE_INFO"
            # Don't require container content type for fallback - just use what's available
            STORAGE=$common_storage
            break
        fi
    done
    
    if [ -z "$STORAGE" ]; then
        error "No usable storage found. The issue is likely:"
        error "1. Storage exists but container content type not enabled"
        error "2. Storage permissions are incorrect"
        error "3. Storage is not properly mounted"
        echo ""
        error "Please configure at least one storage location with container support in Proxmox."
        exit 1
    fi
elif [ ${#STORAGE_LIST[@]} -eq 1 ]; then
    STORAGE=${STORAGE_LIST[0]}
    info "Using single storage location: $STORAGE"
else
    info "Multiple storage locations detected:"
    PS3="Select storage location to use: "
    select storage_item in "${STORAGE_LIST[@]}"; do
        if [[ " ${STORAGE_LIST[*]} " =~ " ${storage_item} " ]]; then
            STORAGE=$storage_item
            break
        fi
        echo "Invalid selection. Please try again."
    done
fi

info "Selected storage: $STORAGE"

# Validate storage accessibility more thoroughly
info "Validating storage accessibility for: $STORAGE"

# Check if storage exists and is accessible
STORAGE_DETAILS=$(pvesm status 2>/dev/null | grep "^$STORAGE[[:space:]]")
if [ -z "$STORAGE_DETAILS" ]; then
    error "Storage $STORAGE not found in available storages"
    error "Available storages:"
    pvesm status 2>/dev/null || error "Could not get storage status"
    exit 1
fi

# Display storage details
info "Storage $STORAGE details: $STORAGE_DETAILS"

# Check if storage supports containers
if ! echo "$STORAGE_DETAILS" | grep -q "rootdir\|vztmpl"; then
    warn "Storage $STORAGE does not have container content type configured"
    warn "Required content types: rootdir or vztmpl"
    warn "Available content types: $(echo "$STORAGE_DETAILS" | grep -o 'content: [^[:space:]]*' || echo 'none')"
    warn ""
    warn "This storage can be configured for containers in Proxmox web interface:"
    configure_storage_for_containers "$STORAGE"
    warn "Continuing with current configuration - you may need to configure the storage first"
    # Don't fail here - let the user try to use it
fi

# Test if we can actually create containers in this storage
info "Testing container creation capability in storage $STORAGE..."
if ! pvesm list "$STORAGE" >/dev/null 2>&1; then
    error "Cannot list storage contents - this indicates a permission or configuration issue"
    exit 1
fi

info "Storage $STORAGE validation successful"

# Summary of storage configuration
echo ""
info "=== Storage Configuration Summary ==="
info "Selected storage: $STORAGE"
info "Storage details: $STORAGE_DETAILS"
if echo "$STORAGE_DETAILS" | grep -q "rootdir\|vztmpl"; then
    info "✅ Container content type: ENABLED"
else
    warn "⚠️  Container content type: NOT CONFIGURED"
    warn "You may need to enable container support in Proxmox web interface"
    configure_storage_for_containers "$STORAGE"
fi
info "====================================="
echo ""

echo "=== Test completed successfully ==="