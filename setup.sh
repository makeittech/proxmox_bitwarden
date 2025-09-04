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
msg_info "Hostname: $HN"
msg_info "Access Bitwarden at: http://\$(pct exec $CTID ip a s dev eth0 | awk '/inet / {print \$2}' | cut -d/ -f1):8080"

echo "###########################"
echo "Setup : complete"
echo "###########################"
