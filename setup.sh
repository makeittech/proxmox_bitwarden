#!/bin/bash -e

# Set error handling
set -Eeuo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration variables
var_os="${var_os:-ubuntu}"
var_version="${var_version:-22.04}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-50}"
var_swap="${var_swap:-4096}"
var_unprivileged="${var_unprivileged:-1}"

# Message functions
msg_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
msg_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
msg_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
msg_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Error handler
error_handler() {
    local exit_code="$?"
    local line_number="$1"
    local command="$2"
    msg_error "in line $line_number: exit code $exit_code: while executing command $command"
    exit "$exit_code"
}

# Set trap for error handling
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR

# Prerequisites check
check_prerequisites() {
    # Check if running as root
    if [[ "$(id -u)" -ne 0 ]]; then
        msg_error "This script must be run as root"
        exit 1
    fi
    
    # Check if running on Proxmox
    if ! command -v pct >/dev/null 2>&1; then
        msg_error "This script must be run on a Proxmox VE host"
        exit 1
    fi
    
    # Check Proxmox version
    local pve_version
    pve_version=$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')
    if [[ ! "$pve_version" =~ ^[89]\. ]]; then
        msg_warn "Proxmox VE version $pve_version detected. This script is tested with versions 8.x and 9.x"
    fi
}

# Storage selection function
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

# Template management
manage_template() {
    local template_storage="$1"
    local os_type="$2"
    local os_version="$3"
    
    msg_info "Managing template for $os_type $os_version..."
    
    # Update template list
    pveam update >/dev/null 2>&1 || msg_warn "Failed to update template list"
    
    # Search for template
    local template_pattern
    case "$os_type" in
        ubuntu|debian) template_pattern="-standard_" ;;
        *) template_pattern="-default_" ;;
    esac
    
    local template
    template=$(pveam available -section system 2>/dev/null | grep "${os_type}-${os_version}${template_pattern}" | tail -1)
    
    if [[ -z "$template" ]]; then
        msg_error "No template found for $os_type $os_version"
        return 1
    fi
    
    msg_info "Found template: $template"
    
    # Check if template exists locally
    if ! pvesm list "$template_storage" | grep -q "$template"; then
        msg_info "Downloading template to $template_storage..."
        if ! pveam download "$template_storage" "$template" >/dev/null 2>&1; then
            msg_error "Failed to download template"
            return 1
        fi
    fi
    
    echo "$template"
}

# Container creation
create_container() {
    local ctid="$1"
    local template_storage="$2"
    local container_storage="$3"
    local template="$4"
    
    msg_info "Creating LXC container $ctid..."
    
    # Set features based on container type
    local features="nesting=1"
    if [[ "${var_unprivileged:-1}" == "1" ]]; then
        features="keyctl=1,nesting=1"
    fi
    
    # Create container
    if ! pct create "$ctid" "${template_storage}:vztmpl/${template}" \
        -arch "$(dpkg --print-architecture)" \
        -cores "${var_cpu:-2}" \
        -memory "${var_ram:-4096}" \
        -swap "${var_swap:-4096}" \
        -onboot 1 \
        -features "$features" \
        -hostname "${HOSTNAME}" \
        -net0 "name=eth0,bridge=${BRG},ip=${NET}${GATE}" \
        -ostype "${var_os:-ubuntu}" \
        -password "${HOSTPASS}" \
        -storage "$container_storage" \
        -rootfs "${container_storage}:${var_disk:-50}"; then
        msg_error "Failed to create container"
        return 1
    fi
    
    msg_ok "Container created successfully"
}

# Main execution
main() {
    echo "###########################"
    echo "Bitwarden Setup Script"
    echo "###########################"
    
    # Check prerequisites
    check_prerequisites
    
    # Get user input
    read -p "Enter hostname (vault-1): " HOSTNAME
    read -s -p "Enter password (bitwarden): " HOSTPASS
    echo -e "\n"
    read -p "Enter container ID (auto): " CONTAINER_ID
    
    # Set defaults
    HOSTNAME="${HOSTNAME:-vault-1}"
    HOSTPASS="${HOSTPASS:-bitwarden}"
    CONTAINER_ID="${CONTAINER_ID:-$(pvesh get /cluster/nextid 2>/dev/null || echo "100")}"
    
    # Validate container ID
    if [[ ! "$CONTAINER_ID" =~ ^[0-9]+$ ]] || [ "$CONTAINER_ID" -lt 100 ]; then
        msg_error "Container ID must be a number >= 100"
        exit 1
    fi
    
    # Check if ID is in use
    if qm status "$CONTAINER_ID" &>/dev/null || pct status "$CONTAINER_ID" &>/dev/null; then
        msg_error "Container ID $CONTAINER_ID is already in use"
        exit 1
    fi
    
    # Network configuration
    msg_info "Detecting network configuration..."
    BRG=$(ip route | grep default | awk '{print $3}' | head -n1 | cut -d'.' -f1)
    if [[ -z "$BRG" ]] || [[ ! "$BRG" =~ ^vmbr[0-9]+$ ]]; then
        BRG="vmbr0"
        msg_warn "Using default bridge: $BRG"
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
    
    # Storage selection
    msg_info "Selecting storage locations..."
    
    TEMPLATE_STORAGE=$(select_storage "vztmpl" "templates")
    if [[ $? -ne 0 ]]; then
        msg_error "Failed to select template storage"
        exit 1
    fi
    
    # Clean up storage name (remove any extra text)
    TEMPLATE_STORAGE=$(echo "$TEMPLATE_STORAGE" | tr -d '\n\r' | xargs)
    msg_info "Selected template storage: '$TEMPLATE_STORAGE'"
    
    CONTAINER_STORAGE=$(select_storage "rootdir" "containers")
    if [[ $? -ne 0 ]]; then
        msg_error "Failed to select container storage"
        exit 1
    fi
    
    # Clean up storage name (remove any extra text)
    CONTAINER_STORAGE=$(echo "$CONTAINER_STORAGE" | tr -d '\n\r' | xargs)
    msg_info "Selected container storage: '$CONTAINER_STORAGE'"
    
    msg_ok "Template storage: $TEMPLATE_STORAGE"
    msg_ok "Container storage: $CONTAINER_STORAGE"
    
    # Template management
    TEMPLATE=$(manage_template "$TEMPLATE_STORAGE" "${var_os:-ubuntu}" "${var_version:-22.04}")
    if [[ $? -ne 0 ]]; then
        msg_error "Failed to manage template"
        exit 1
    fi
    
    # Create container
    if ! create_container "$CONTAINER_ID" "$TEMPLATE_STORAGE" "$CONTAINER_STORAGE" "$TEMPLATE"; then
        exit 1
    fi
    
    # Start container
    msg_info "Starting container..."
    pct start "$CONTAINER_ID" || {
        msg_error "Failed to start container"
        exit 1
    }
    
    # Wait for container to be ready
    msg_info "Waiting for container to be ready..."
    for i in {1..30}; do
        if pct status "$CONTAINER_ID" | grep -q "status: running"; then
            break
        fi
        sleep 1
        if [ "$i" -eq 30 ]; then
            msg_error "Container failed to start"
            exit 1
        fi
    done
    
    # Wait for network
    msg_info "Waiting for network..."
    for i in {1..30}; do
        if pct exec "$CONTAINER_ID" -- ping -c1 -W1 8.8.8.8 >/dev/null 2>&1; then
            break
        fi
        sleep 1
        if [ "$i" -eq 30 ]; then
            msg_warn "Network not ready, continuing anyway"
        fi
    done
    
    # Setup OS
    msg_info "Setting up OS..."
    pct exec "$CONTAINER_ID" -- bash -c "
        apt-get update >/dev/null 2>&1
        apt-get install -y curl wget gnupg2 software-properties-common >/dev/null 2>&1
        timedatectl set-timezone UTC >/dev/null 2>&1
        locale-gen en_US.UTF-8 >/dev/null 2>&1
        update-locale LANG=en_US.UTF-8 >/dev/null 2>&1
    " || msg_warn "OS setup had some issues"
    
    # Setup Docker
    msg_info "Setting up Docker..."
    pct exec "$CONTAINER_ID" -- bash -c "
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu jammy stable' > /etc/apt/sources.list.d/docker.list
        apt-get update >/dev/null 2>&1
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
        systemctl enable docker >/dev/null 2>&1
        systemctl start docker >/dev/null 2>&1
    " || msg_warn "Docker setup had some issues"
    
    # Setup Bitwarden
    msg_info "Setting up Bitwarden..."
    pct exec "$CONTAINER_ID" -- bash -c "
        mkdir -p /opt/bitwarden
        cd /opt/bitwarden
        curl -Lso bitwarden.sh https://func.bitwarden.com/api/dl/?app=self-host >/dev/null 2>&1
        chmod +x bitwarden.sh
        ./bitwarden.sh install --acceptlicense >/dev/null 2>&1
    " || msg_warn "Bitwarden setup had some issues"
    
    # Final restart
    msg_info "Final container restart..."
    pct reboot "$CONTAINER_ID"
    
    # Wait for restart
    sleep 15
    
    msg_ok "Setup complete!"
    msg_info "Container ID: $CONTAINER_ID"
    msg_info "Hostname: $HOSTNAME"
    if [[ "$IP_CONFIG" != "auto" && "$IP_CONFIG" != "dhcp" ]]; then
        msg_info "Access Bitwarden at: http://$IP_CONFIG:8080"
    else
        msg_info "Container is using DHCP. Check Proxmox interface for assigned IP."
    fi
    
    echo "###########################"
    echo "Setup : complete"
    echo "###########################"
}

# Run main function
main "$@"
