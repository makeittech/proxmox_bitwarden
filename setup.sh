#!/usr/bin/env bash

# Import the community scripts build system (same as AdGuard script)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Application configuration (same pattern as AdGuard script)
APP="Bitwarden"
var_tags="${var_tags:-password-manager}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-50}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-22.04}"
var_unprivileged="${var_unprivileged:-1}"

# Load functions and setup (same as AdGuard script)
header_info "$APP"
variables
color
catch_errors

# Check prerequisites
shell_check
root_check
pve_check

# Get user input for basic settings
read -p "Enter a hostname (bitwarden): " HOSTNAME
read -s -p "Enter a password (bitwarden): " HOSTPASS
echo -e "\n"
read -p "Enter a container ID (auto): " CONTAINER_ID

# Set defaults if no input provided
HOSTNAME="${HOSTNAME:-bitwarden}"
HOSTPASS="${HOSTPASS:-bitwarden}"
CONTAINER_ID="${CONTAINER_ID:-$(pvesh get /cluster/nextid 2>/dev/null || echo "100")}"

# Validate container ID
if [ "$CONTAINER_ID" -lt 100 ]; then
    msg_error "Container ID must be 100 or higher"
    exit 1
fi

# Check if ID is already in use
if qm status "$CONTAINER_ID" &>/dev/null || pct status "$CONTAINER_ID" &>/dev/null; then
    msg_error "Container ID $CONTAINER_ID is already in use"
    exit 1
fi

# Set global variables for container creation (same as AdGuard script)
CTID="$CONTAINER_ID"
HN="$HOSTNAME"
PW="-password $HOSTPASS"
TAGS="$var_tags"
CORE_COUNT="$var_cpu"
RAM_SIZE="$var_ram"
DISK_SIZE="$var_disk"
CT_TYPE="$var_unprivileged"
PCT_OSTYPE="$var_os"
PCT_OSVERSION="$var_version"

# Additional variables required by the build system
MAC=""
VLAN=""
MTU="1500"
SD=""
NS=""
SSH="no"
SSH_AUTHORIZED_KEY=""
ENABLE_FUSE="no"
ENABLE_TUN="no"
APT_CACHER=""
APT_CACHER_IP=""

# IPv6 variables required by the build system
IPV6_METHOD="none"
IPV6_ADDR=""
IPV6_GATE=""

# Network configuration (same as AdGuard script)
msg_info "Detecting network configuration..."
BRG=$(ip route | grep default | awk '{print $3}' | head -n1 | cut -d'.' -f1)
if [ -z "$BRG" ] || [[ ! "$BRG" =~ ^vmbr[0-9]+$ ]]; then
    BRG="vmbr0"
    msg_warn "Could not detect network bridge, using default: $BRG"
fi

# Get IP configuration
echo -e "\nNetwork Configuration:"
read -p "IP Address (192.168.1.29 or auto): " IP_CONFIG
IP_CONFIG="${IP_CONFIG:-192.168.1.29}"

if [[ "$IP_CONFIG" == "auto" || "$IP_CONFIG" == "dhcp" ]]; then
    msg_info "Using DHCP"
    NET="ip=dhcp"
    GATE=""
else
    read -p "Subnet mask (24): " SUBNET_MASK
    SUBNET_MASK="${SUBNET_MASK:-24}"
    IP_WITH_SUBNET="${IP_CONFIG}/${SUBNET_MASK}"
    
    DEFAULT_GATEWAY=$(echo "$IP_CONFIG" | cut -d'.' -f1-3).1
    read -p "Gateway ($DEFAULT_GATEWAY): " GATEWAY
    GATEWAY="${GATEWAY:-$DEFAULT_GATEWAY}"
    
    NET="ip=$IP_WITH_SUBNET"
    GATE=",gw=$GATEWAY"
fi

# Set storage variables (same as AdGuard script)
STORAGE=""
SD=""

# Create container using the community scripts build system (same as AdGuard script)
msg_info "Creating LXC container..."
build_container

# Wait for container to be ready
msg_info "Waiting for container to be ready..."
sleep 10

# Check container status
if ! pct status "$CTID" | grep -q "status: running"; then
    msg_error "Container $CTID is not running properly!"
    exit 1
fi

msg_ok "Container is running successfully"

# Setup OS
msg_info "Setting up OS..."
pct exec "$CTID" -- bash -c "
    # Update system
    apt-get update >/dev/null 2>&1
    apt-get install -y curl wget gnupg2 software-properties-common >/dev/null 2>&1
    
    # Set timezone
    timedatectl set-timezone UTC >/dev/null 2>&1
    
    # Configure locale
    locale-gen en_US.UTF-8 >/dev/null 2>&1
    update-locale LANG=en_US.UTF-8 >/dev/null 2>&1
" || msg_warn "OS setup had some issues"

# Setup Docker
msg_info "Setting up Docker..."
pct exec "$CTID" -- bash -c "
    # Install Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu jammy stable' > /etc/apt/sources.list.d/docker.list
    apt-get update >/dev/null 2>&1
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
    
    # Start and enable Docker
    systemctl enable docker >/dev/null 2>&1
    systemctl start docker >/dev/null 2>&1
" || msg_warn "Docker setup had some issues"

# Setup Bitwarden
msg_info "Setting up Bitwarden..."
pct exec "$CTID" -- bash -c "
    # Create Bitwarden directory
    mkdir -p /opt/bitwarden
    cd /opt/bitwarden
    
    # Download and setup Bitwarden
    curl -Lso bitwarden.sh https://func.bitwarden.com/api/dl/?app=self-host >/dev/null 2>&1
    chmod +x bitwarden.sh
    ./bitwarden.sh install --acceptlicense >/dev/null 2>&1
" || msg_warn "Bitwarden setup had some issues"

# Final restart
msg_info "Final container restart..."
pct reboot "$CTID"

# Wait for restart
sleep 15

msg_ok "Container and app setup complete!"
msg_info "Container ID: $CTID"
msg_info "Hostname: $HOSTNAME"
if [[ "$IP_CONFIG" != "auto" && "$IP_CONFIG" != "dhcp" ]]; then
    msg_info "Access Bitwarden at: http://$IP_CONFIG:8080"
else
    msg_info "Container is using DHCP. Check Proxmox interface for assigned IP."
fi

echo "###########################"
echo "Setup : complete"
echo "###########################"
