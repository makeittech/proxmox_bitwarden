#!/bin/bash -e

# functions
function fatal() {
    echo -e "\e[91m[FATAL] $1\e[39m"
    exit 1
}
function error() {
    echo -e "\e[91m[ERROR] $1\e[39m"
}
function warn() {
    echo -e "\e[93m[WARNING] $1\e[39m"
}
function info() {
    echo -e "\e[36m[INFO] $1\e[39m"
}
function cleanup() {
    if [ -n "$TEMP_FOLDER_PATH" ] && [ -d "$TEMP_FOLDER_PATH" ]; then
        popd >/dev/null 2>&1 || true
        rm -rf "$TEMP_FOLDER_PATH"
    fi
}

function troubleshoot_storage() {
    echo -e "\n\e[93m=== Storage Troubleshooting ===\e[39m"
    echo "1. Check if Proxmox storage is properly configured:"
    echo "   - Go to Datacenter > Storage in Proxmox web interface"
    echo "   - Ensure at least one storage has 'Container' content type enabled"
    echo "   - Common storage names: local, local-lvm, local-zfs"
    echo ""
    echo "2. Verify storage permissions:"
    echo "   - Check if storage directories exist and are writable"
    echo "   - Ensure Proxmox user has access to storage locations"
    echo ""
    echo "3. Check storage status:"
    echo "   - Run: pvesm status"
    echo "   - Look for storages with 'rootdir' or 'vztmpl' content types"
    echo ""
    echo "4. Common issues:"
    echo "   - Storage not mounted or accessible"
    echo "   - Insufficient disk space"
    echo "   - Permission denied errors"
    echo "   - Storage content type not configured for containers"
    echo -e "\e[93m==============================\e[39m\n"
}

# Set trap for cleanup on exit
trap cleanup EXIT

echo "###########################"
echo "Setup : begin"
echo "###########################"

TEMP_FOLDER_PATH=$(mktemp -d)
pushd "$TEMP_FOLDER_PATH" >/dev/null

# Container configuration
DEFAULT_HOSTNAME='vault-1'
DEFAULT_PASSWORD='bitwarden'
DEFAULT_CONTAINER_ID=$(pvesh get /cluster/nextid 2>/dev/null || echo "100")

# Get user input for basic settings
read -p "Enter a hostname (${DEFAULT_HOSTNAME}) : " HOSTNAME
read -s -p "Enter a password (${DEFAULT_HOSTNAME}) : " HOSTPASS
echo -e "\n"
read -p "Enter a container ID (${DEFAULT_CONTAINER_ID}) : " CONTAINER_ID

# Set defaults if no input provided
HOSTNAME="${HOSTNAME:-${DEFAULT_HOSTNAME}}"
HOSTPASS="${HOSTPASS:-${DEFAULT_PASSWORD}}"
CONTAINER_ID="${CONTAINER_ID:-${DEFAULT_CONTAINER_ID}}"

# Container OS configuration
CONTAINER_OS_TYPE='ubuntu'
CONTAINER_OS_VERSION='ubuntu-22.04-standard_22.04-1_amd64.tar.zst'

# Discover available storage locations
info "Discovering available storage locations..."

# Debug: Show all available storages first
info "All available storages:"
pvesm status 2>/dev/null || warn "Could not get storage status"

# First, try to get all available storages
STORAGE_LIST=($(pvesm status 2>/dev/null | awk 'NR>1 {print $1}' | grep -v '^$'))

# If that fails, try alternative methods
if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
    # Try getting storages with container content type
    STORAGE_LIST=($(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 {print $1}' | grep -v '^$'))
fi

# If still no storages found, try getting all storages without content filter
if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
    STORAGE_LIST=($(pvesm status 2>/dev/null | awk 'NR>1 {print $1}' | grep -v '^$'))
fi

# Filter out storages that are not accessible or don't support containers
ACCESSIBLE_STORAGES=()
info "Checking storage accessibility and container support..."

for storage in "${STORAGE_LIST[@]}"; do
    info "Checking storage: $storage"
    
    # Check if storage is accessible
    if ! pvesm status "$storage" >/dev/null 2>&1; then
        warn "Storage $storage is not accessible"
        continue
    fi
    
    # Get storage details
    STORAGE_INFO=$(pvesm status "$storage" 2>/dev/null)
    info "Storage $storage details: $STORAGE_INFO"
    
    # Check if storage supports containers (has rootdir or vztmpl content type)
    if echo "$STORAGE_INFO" | grep -q "rootdir\|vztmpl"; then
        info "Storage $storage supports containers"
        ACCESSIBLE_STORAGES+=("$storage")
    else
        warn "Storage $storage does not support containers (missing rootdir or vztmpl content type)"
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
        if pvesm status "$common_storage" >/dev/null 2>&1; then
            STORAGE_INFO=$(pvesm status "$common_storage" 2>/dev/null)
            if echo "$STORAGE_INFO" | grep -q "rootdir\|vztmpl"; then
                info "Found working storage: $common_storage"
                STORAGE=$common_storage
                break
            fi
        fi
    done
    
    if [ -z "$STORAGE" ]; then
        troubleshoot_storage
        fatal "Please configure at least one storage location with container support in Proxmox."
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
if ! pvesm status "$STORAGE" >/dev/null 2>&1; then
    error "Storage $STORAGE status check failed"
    error "Available storages:"
    pvesm status 2>/dev/null || error "Could not get storage status"
    troubleshoot_storage
    fatal "Storage $STORAGE is not accessible"
fi

# Get and display storage details
STORAGE_DETAILS=$(pvesm status "$STORAGE" 2>/dev/null)
info "Storage $STORAGE details: $STORAGE_DETAILS"

# Check if storage supports containers
if ! echo "$STORAGE_DETAILS" | grep -q "rootdir\|vztmpl"; then
    error "Storage $STORAGE does not support containers"
    error "Required content types: rootdir or vztmpl"
    error "Available content types: $(echo "$STORAGE_DETAILS" | grep -o 'content: [^[:space:]]*' || echo 'none')"
    troubleshoot_storage
    fatal "Storage $STORAGE does not support containers (missing rootdir or vztmpl content type)"
fi

# Check if we can list storage contents
if ! pvesm list "$STORAGE" >/dev/null 2>&1; then
    error "Cannot list contents of storage $STORAGE"
    error "Storage might be read-only or have permission issues"
    troubleshoot_storage
    fatal "Cannot access storage $STORAGE contents"
fi

info "Storage $STORAGE validation successful"

# Check available disk space
info "Checking available disk space..."
if command -v df >/dev/null 2>&1; then
    # Get storage path and check space
    STORAGE_PATH=$(pvesm status "$STORAGE" | grep -o 'path: [^[:space:]]*' | cut -d' ' -f2)
    if [ -n "$STORAGE_PATH" ] && [ -d "$STORAGE_PATH" ]; then
        AVAILABLE_SPACE=$(df -BG "$STORAGE_PATH" | awk 'NR==2 {print $4}' | sed 's/G//')
        if [ -n "$AVAILABLE_SPACE" ] && [ "$AVAILABLE_SPACE" -lt 10 ]; then
            warn "Low disk space: ${AVAILABLE_SPACE}G available. At least 10G recommended for container creation."
        else
            info "Available disk space: ${AVAILABLE_SPACE}G"
        fi
    fi
fi

# Check if template exists, download if not
TEMPLATE_LOCATION="${STORAGE}:vztmpl/${CONTAINER_OS_VERSION}"
info "Checking template availability: ${TEMPLATE_LOCATION}"

if ! pvesm status "$STORAGE" >/dev/null 2>&1; then
    fatal "Storage $STORAGE is not accessible"
fi

# Check if template exists in storage
info "Checking for template $CONTAINER_OS_VERSION in storage $STORAGE..."

# First, try to list the storage contents
if ! pvesm list "$STORAGE" >/dev/null 2>&1; then
    fatal "Cannot access storage $STORAGE contents"
fi

# Check if template exists
if pvesm list "$STORAGE" | grep -q "$CONTAINER_OS_VERSION"; then
    info "Template $CONTAINER_OS_VERSION found in storage $STORAGE"
else
    info "Template $CONTAINER_OS_VERSION not found in storage $STORAGE. Downloading..."
    
    # Update available templates
    info "Updating available templates..."
    if ! pveam update >/dev/null 2>&1; then
        warn "Failed to update template list, continuing anyway..."
    fi
    
    # Download the specific Ubuntu 22.04 template
    info "Downloading template $CONTAINER_OS_VERSION to storage $STORAGE..."
    if ! pveam download "$STORAGE" "$CONTAINER_OS_VERSION" >/dev/null 2>&1; then
        error "Failed to download template $CONTAINER_OS_VERSION to storage $STORAGE"
        troubleshoot_storage
        fatal "Template download failed. Check storage accessibility and available space."
    fi
    
    info "Template downloaded successfully"
fi

# Get network configuration from Proxmox defaults
info "Detecting network configuration..."
NET_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -z "$NET_INTERFACE" ]; then
    NET_INTERFACE="eth0"
    warn "Could not detect network interface, using default: $NET_INTERFACE"
fi

# Get default bridge (usually vmbr0)
NET_BRIDGE=$(ip route | grep default | awk '{print $3}' | head -n1 | cut -d'.' -f1)
if [ -z "$NET_BRIDGE" ] || [[ ! "$NET_BRIDGE" =~ ^vmbr[0-9]+$ ]]; then
    NET_BRIDGE="vmbr0"
    warn "Could not detect network bridge, using default: $NET_BRIDGE"
fi

# Get IP configuration - try DHCP first, fallback to static
info "Network interface: $NET_INTERFACE, Bridge: $NET_BRIDGE"
info "IP configuration will use DHCP by default. You can configure static IP later in the container."

# Create the container
info "Creating LXC container..."
CONTAINER_ARCH=$(dpkg --print-architecture)
info "Using ARCH: ${CONTAINER_ARCH}"

# Create container with DHCP network configuration
pct create "${CONTAINER_ID}" "${TEMPLATE_LOCATION}" \
    -arch "${CONTAINER_ARCH}" \
    -cores 2 \
    -memory 4096 \
    -swap 4096 \
    -onboot 1 \
    -features nesting=1 \
    -hostname "${HOSTNAME}" \
    -net0 name=${NET_INTERFACE},bridge=${NET_BRIDGE},dhcp=1 \
    -ostype "${CONTAINER_OS_TYPE}" \
    -password "${HOSTPASS}" \
    -storage "${STORAGE}" || fatal "Failed to create LXC container!"

# Configure container
info "Configuring LXC container..."
pct resize "${CONTAINER_ID}" rootfs 50G || fatal "Failed to expand root volume!"

# Start container
info "Starting LXC container..."
pct start "${CONTAINER_ID}" || fatal "Failed to start container!"

# Wait for container to be fully running
info "Waiting for container to be ready..."
sleep 10

# Check container status
CONTAINER_STATUS=$(pct status "$CONTAINER_ID" 2>/dev/null | grep -o "status: [a-z]*" | cut -d' ' -f2)
if [ "$CONTAINER_STATUS" != "running" ]; then
    warn "Container status: $CONTAINER_STATUS"
    fatal "Container ${CONTAINER_ID} is not running properly!"
fi

info "Container is running successfully"

# Setup OS
info "Fetching and executing OS setup script..."
wget -qL https://raw.githubusercontent.com/noofny/proxmox_bitwarden/master/setup_os.sh || \
    fatal "Failed to download setup_os.sh"
pct push "${CONTAINER_ID}" ./setup_os.sh /setup_os.sh -perms 755
pct exec "${CONTAINER_ID}" -- bash -c "/setup_os.sh" || warn "OS setup script had issues"
pct reboot "${CONTAINER_ID}"

# Wait for container to come back up
info "Waiting for container to restart..."
sleep 15

# Setup docker
info "Fetching and executing Docker setup script..."
wget -qL https://raw.githubusercontent.com/noofny/proxmox_bitwarden/master/setup_docker.sh || \
    fatal "Failed to download setup_docker.sh"
pct push "${CONTAINER_ID}" ./setup_docker.sh /setup_docker.sh -perms 755
pct exec "${CONTAINER_ID}" -- bash -c "/setup_docker.sh" || warn "Docker setup script had issues"
pct reboot "${CONTAINER_ID}"

# Wait for container to come back up
info "Waiting for container to restart..."
sleep 15

# Setup Bitwarden
info "Fetching and executing Bitwarden setup script..."
wget -qL https://raw.githubusercontent.com/noofny/proxmox_bitwarden/master/setup_bitwarden.sh || \
    fatal "Failed to download setup_bitwarden.sh"
pct push "${CONTAINER_ID}" ./setup_bitwarden.sh /setup_bitwarden.sh -perms 755
pct exec "${CONTAINER_ID}" -- bash -c "/setup_bitwarden.sh" || warn "Bitwarden setup script had issues"

# Final reboot
info "Final container restart..."
pct reboot "${CONTAINER_ID}"

info "Container and app setup complete! Container will restart."
info "Container ID: $CONTAINER_ID"
info "Hostname: $HOSTNAME"
info "Storage: $STORAGE"
info "Network: $NET_INTERFACE on $NET_BRIDGE"

echo "###########################"
echo "Setup : complete"
echo "###########################"
