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

# Use the start function to handle all user input and variable setting (same as AdGuard script)
start

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
