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
STORAGE_LIST=($(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 {print $1}' | grep -v '^$'))

if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
    fatal "No storage locations with 'Container' content type found. Please configure at least one storage location in Proxmox."
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

# Check if template exists, download if not
TEMPLATE_LOCATION="${STORAGE}:vztmpl/${CONTAINER_OS_VERSION}"
info "Checking template availability: ${TEMPLATE_LOCATION}"

if ! pvesm status "$STORAGE" >/dev/null 2>&1; then
    fatal "Storage $STORAGE is not accessible"
fi

# Check if template exists in storage
if ! pvesm list "$STORAGE" | grep -q "$CONTAINER_OS_VERSION"; then
    info "Template $CONTAINER_OS_VERSION not found in storage $STORAGE. Downloading..."
    
    # Update available templates
    pveam update
    
    # Download the specific Ubuntu 22.04 template
    if ! pveam download "$STORAGE" "$CONTAINER_OS_VERSION"; then
        fatal "Failed to download template $CONTAINER_OS_VERSION to storage $STORAGE"
    fi
    
    info "Template downloaded successfully"
else
    info "Template $CONTAINER_OS_VERSION found in storage $STORAGE"
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
