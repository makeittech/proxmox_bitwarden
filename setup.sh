#!/usr/bin/env bash

# Import the community scripts build system (same as AdGuard script)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Application configuration (same pattern as AdGuard script)
APP="Bitwarden"
var_tags="${var_tags:-password-manager}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-22.04}"
var_unprivileged="${var_unprivileged:-1}"
var_install="${var_install:-}"

# Custom container creation function (based on build_container but without automatic installation)
create_custom_container() {
  NET_STRING="-net0 name=eth0,bridge=$BRG$MAC,ip=$NET$GATE$VLAN$MTU"
  case "$IPV6_METHOD" in
  auto) NET_STRING="$NET_STRING,ip6=auto" ;;
  dhcp) NET_STRING="$NET_STRING,ip6=dhcp" ;;
  static)
    NET_STRING="$NET_STRING,ip6=$IPV6_ADDR"
    [ -n "$IPV6_GATE" ] && NET_STRING="$NET_STRING,gw6=$IPV6_GATE"
    ;;
  none) ;;
  esac
  if [ "$CT_TYPE" == "1" ]; then
    FEATURES="keyctl=1,nesting=1"
  else
    FEATURES="nesting=1"
  fi

  if [ "$ENABLE_FUSE" == "yes" ]; then
    FEATURES="$FEATURES,fuse=1"
  fi

  TEMP_DIR=$(mktemp -d)
  pushd "$TEMP_DIR" >/dev/null
  
  export FUNCTIONS_FILE_PATH="$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/install.func)"
  export DIAGNOSTICS="$DIAGNOSTICS"
  export RANDOM_UUID="$RANDOM_UUID"
  export CACHER="$APT_CACHER"
  export CACHER_IP="$APT_CACHER_IP"
  export tz="$timezone"
  export APPLICATION="$APP"
  export app="$NSAPP"
  export PASSWORD="$PW"
  export VERBOSE="$VERBOSE"
  export SSH_ROOT="${SSH}"
  export SSH_AUTHORIZED_KEY
  export CTID="$CT_ID"
  export CTTYPE="$CT_TYPE"
  export ENABLE_FUSE="$ENABLE_FUSE"
  export ENABLE_TUN="$ENABLE_TUN"
  export PCT_OSTYPE="$var_os"
  export PCT_OSVERSION="$var_version"
  export PCT_DISK_SIZE="$DISK_SIZE"
  export PCT_OPTIONS="
    -features $FEATURES
    -hostname $HN
    -tags $TAGS
    $SD
    $NS
    $NET_STRING
    -onboot 1
    -cores $CORE_COUNT
    -memory $RAM_SIZE
    -unprivileged $CT_TYPE
    $PW
  "
  
  # Create the container
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/create_lxc.sh)" $?
  
  LXC_CONFIG="/etc/pve/lxc/${CTID}.conf"

  # Start the container
  msg_info "Starting LXC Container"
  pct start "$CTID"

  # Wait for container to be running
  for i in {1..10}; do
    if pct status "$CTID" | grep -q "status: running"; then
      msg_ok "Started LXC Container"
      break
    fi
    sleep 1
    if [ "$i" -eq 10 ]; then
      msg_error "LXC Container did not reach running state"
      exit 1
    fi
  done

  # Wait for network
  msg_info "Waiting for network in LXC container"
  for i in {1..10}; do
    if pct exec "$CTID" -- ping -c1 -W1 deb.debian.org >/dev/null 2>&1; then
      msg_ok "Network in LXC is reachable (ping)"
      break
    fi
    if [ "$i" -lt 10 ]; then
      msg_warn "No network in LXC yet (try $i/10) – waiting..."
      sleep 3
    else
      msg_warn "Ping failed 10 times. Trying HTTP connectivity check (wget) as fallback..."
      if pct exec "$CTID" -- wget -q --spider http://deb.debian.org; then
        msg_ok "Network in LXC is reachable (wget fallback)"
      else
        msg_error "No network in LXC after all checks."
        exit 1
      fi
      break
    fi
  done

  # Customize container
  msg_info "Customizing LXC Container"
  : "${tz:=Etc/UTC}"
  sleep 3
  pct exec "$CTID" -- bash -c "sed -i '/$LANG/ s/^# //' /etc/locale.gen"
  pct exec "$CTID" -- bash -c "locale_line=\$(grep -v '^#' /etc/locale.gen | grep -E '^[a-zA-Z]' | awk '{print \$1}' | head -n 1) && \
    echo LANG=\$locale_line >/etc/default/locale && \
    locale-gen >/dev/null && \
    export LANG=\$locale_line"

  if [[ -z "${tz:-}" ]]; then
    tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Etc/UTC")
  fi
  if pct exec "$CTID" -- test -e "/usr/share/zoneinfo/$tz"; then
    pct exec "$CTID" -- bash -c "tz='$tz'; echo \"\$tz\" >/etc/timezone && ln -sf \"/usr/share/zoneinfo/\$tz\" /etc/localtime"
  else
    msg_warn "Skipping timezone setup – zone '$tz' not found in container"
  fi

  pct exec "$CTID" -- bash -c "apt-get update >/dev/null && apt-get install -y sudo curl mc gnupg2 jq >/dev/null"
  msg_ok "Customized LXC Container"
  
  popd >/dev/null
  rm -rf "$TEMP_DIR"
}

# Load functions and setup (same as AdGuard script)
header_info "$APP"
variables
# Override var_install to prevent automatic installation script download
var_install=""
color
catch_errors

# Use the start function to handle all user input and variable setting (same as AdGuard script)
start

# Create container using custom function to avoid automatic installation script
msg_info "Creating LXC container..."
create_custom_container

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
    
    # Download Bitwarden installer with multiple fallback URLs
    echo 'Downloading Bitwarden installer...'
    
    # Try multiple download URLs as fallbacks
    DOWNLOAD_URLS=(
        'https://go.btwrdn.co/bw-sh'
        'https://func.bitwarden.com/api/dl/?app=self-host&platform=linux'
        'https://raw.githubusercontent.com/bitwarden/server/master/scripts/bitwarden.sh'
    )
    
    DOWNLOAD_SUCCESS=false
    for url in \"\${DOWNLOAD_URLS[@]}\"; do
        echo \"Trying URL: \$url\"
        curl -Lso bitwarden.sh \"\$url\"
        if [ \$? -eq 0 ] && [ -s bitwarden.sh ]; then
            echo \"Download successful from: \$url\"
            echo \"File size: \$(wc -c < bitwarden.sh) bytes\"
            
            # Check if the file looks like a valid script
            if head -1 bitwarden.sh | grep -q '#!/bin/bash\|#!/usr/bin/env bash'; then
                echo \"Valid script detected, setting permissions...\"
                chmod 700 bitwarden.sh
                echo \"First few lines of downloaded file:\"
                head -5 bitwarden.sh
                DOWNLOAD_SUCCESS=true
                break
            else
                echo \"Downloaded file doesn't appear to be a valid script:\"
                head -5 bitwarden.sh
                echo \"Trying next URL...\"
            fi
        else
            echo \"Failed to download from: \$url\"
        fi
    done
    
    if [ \"\$DOWNLOAD_SUCCESS\" = true ]; then
        echo 'Installing Bitwarden...'
        echo 'Note: Running as root in Proxmox LXC container environment'
        # Get container IP for domain configuration
        CONTAINER_IP=\$(ip a s dev eth0 | awk '/inet / {print \$2}' | cut -d/ -f1)
        echo \"Using container IP: \$CONTAINER_IP as domain\"
        
        # Provide all required inputs for non-interactive installation
        # Use a more comprehensive approach to handle all possible prompts
        echo 'Starting non-interactive installation with inputs:'
        echo '1. y (confirm root user)'
        echo \"2. \$CONTAINER_IP (domain name)\"
        echo '3. n (skip Let'\''s Encrypt SSL)'
        echo '4. vault (database name)'
        echo '5. n (skip admin user setup)'
        
        # Set environment variables to help with non-interactive installation
        export DEBIAN_FRONTEND=noninteractive
        export BITWARDEN_ACCEPT_EULA=true
        export DOCKER_BUILDKIT=0
        export COMPOSE_DOCKER_CLI_BUILD=0
        
        # Try multiple approaches to handle TTY issues
        echo 'Attempting installation with TTY workarounds...'
        
        # Method 1: Try with script command if available
        if command -v script >/dev/null 2>&1; then
            echo 'Method 1: Using script command to create pseudo-TTY'
            printf 'y\n%s\nn\nvault\nn\nn\nn\nn\n' \"\$CONTAINER_IP\" | script -q -c './bitwarden.sh install' /dev/null
            INSTALL_EXIT_CODE=\$?
        else
            echo 'Method 1 failed: script command not available'
            INSTALL_EXIT_CODE=1
        fi
        
        # Method 2: Try with unbuffer if available
        if [ \$INSTALL_EXIT_CODE -ne 0 ] && command -v unbuffer >/dev/null 2>&1; then
            echo 'Method 2: Using unbuffer to handle TTY'
            printf 'y\n%s\nn\nvault\nn\nn\nn\nn\n' \"\$CONTAINER_IP\" | unbuffer ./bitwarden.sh install
            INSTALL_EXIT_CODE=\$?
        fi
        
        # Method 3: Try direct installation with stdbuf
        if [ \$INSTALL_EXIT_CODE -ne 0 ]; then
            echo 'Method 3: Using stdbuf for direct installation'
            printf 'y\n%s\nn\nvault\nn\nn\nn\nn\n' \"\$CONTAINER_IP\" | stdbuf -oL -eL ./bitwarden.sh install
            INSTALL_EXIT_CODE=\$?
        fi
        
        if [ \$INSTALL_EXIT_CODE -ne 0 ]; then
            echo \"Bitwarden installation failed with exit code: \$INSTALL_EXIT_CODE\"
            echo 'Checking installation directory...'
            ls -la /opt/bitwarden/
            echo 'Checking bwdata directory...'
            ls -la /opt/bitwarden/bwdata/ 2>/dev/null || echo 'bwdata directory not found'
            echo 'Checking for any error logs...'
            find /opt/bitwarden -name '*.log' -exec cat {} \; 2>/dev/null || echo 'No log files found'
            echo 'Checking Docker containers...'
            docker ps -a 2>/dev/null || echo 'Docker not available'
            echo 'Checking Docker logs for bitwarden containers...'
            docker logs \$(docker ps -aq --filter 'name=bitwarden') 2>/dev/null || echo 'No bitwarden containers found'
            exit 1
        fi
        
        # Start Bitwarden
        echo 'Starting Bitwarden...'
        # Automatically answer 'y' to any prompts during start
        echo 'y' | ./bitwarden.sh start
        if [ \$? -ne 0 ]; then
            echo 'Failed to start Bitwarden'
            exit 1
        fi
        
        echo 'Bitwarden setup completed successfully'
    else
        echo 'Failed to download Bitwarden installer from all URLs'
        echo 'Please check your internet connection and try again'
        exit 1
    fi
" || {
    msg_error "Bitwarden setup failed!"
    msg_info "Checking container logs..."
    pct exec "$CTID" -- bash -c "cd /opt/bitwarden && ls -la && cat logs/bitwarden.log 2>/dev/null || echo 'No log file found'"
    exit 1
}

# Final restart
msg_info "Final container restart..."
pct reboot "$CTID"

# Wait for restart
sleep 15

# Verify Bitwarden is running
msg_info "Verifying Bitwarden is running..."
pct exec "$CTID" -- bash -c "
    cd /opt/bitwarden
    if ./bitwarden.sh status | grep -q 'running'; then
        echo 'Bitwarden is running successfully'
    else
        echo 'Bitwarden is not running, attempting to start...'
        # Automatically answer 'y' to any prompts during start
        echo 'y' | ./bitwarden.sh start
        sleep 5
        if ./bitwarden.sh status | grep -q 'running'; then
            echo 'Bitwarden started successfully'
        else
            echo 'Failed to start Bitwarden'
            exit 1
        fi
    fi
" || msg_warn "Bitwarden may not be running properly"

# Get container IP address
CONTAINER_IP=$(pct exec "$CTID" ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)

msg_ok "Container and app setup complete!"
echo ""
echo "###########################"
echo "Setup : complete"
echo "###########################"
echo ""
msg_info "Container ID: $CTID"
msg_info "Hostname: $HN"
msg_info "Container IP: $CONTAINER_IP"
echo ""
msg_info "SSH Access:"
msg_info "  Username: root"
msg_info "  Password: [The password you set during setup]"
msg_info "  Command: ssh root@$CONTAINER_IP"
echo ""
msg_info "Bitwarden Access:"
msg_info "  URL: http://$CONTAINER_IP:8080"
msg_info "  Create your admin account on first visit"
echo ""
