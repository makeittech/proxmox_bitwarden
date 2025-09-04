#!/bin/bash -e


echo "###########################"
echo "Setup Bitwarden : begin"
echo "###########################"


# locale
echo "Setting locale..."
LOCALE_VALUE="en_US.UTF-8"
echo ">>> locale-gen..."
locale-gen ${LOCALE_VALUE}
echo ">>> update-locale..."
update-locale ${LOCALE_VALUE}
echo ">>> hack /etc/ssh/ssh_config..."
sed -e '/SendEnv/ s/^#*/#/' -i /etc/ssh/ssh_config


echo "Installing Docker first..."
apt install -y \
    apt-transport-https \
    ca-certificates \
    software-properties-common

# Modern way to add Docker GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update &&
apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-compose
systemctl enable docker
systemctl start docker

echo "Installing Bitwarden..."
# Ensure we're running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

usermod -aG docker root
usermod -aG docker vaultadmin
sudo mkdir /opt/bitwarden
sudo chmod 755 /opt/bitwarden
cd /opt/bitwarden
echo "Downloading Bitwarden installer..."
curl -Lso bitwarden.sh https://go.btwrdn.co/bw-sh
if [ $? -eq 0 ]; then
    echo "Download successful, setting permissions..."
    chmod 700 bitwarden.sh
    echo "File size: $(wc -c < bitwarden.sh) bytes"
    echo "First few lines of downloaded file:"
    head -5 bitwarden.sh
    echo "Installing Bitwarden..."
    ./bitwarden.sh install
else
    echo "Failed to download Bitwarden installer"
    exit 1
fi


echo "Opening config file(s) for editing..."
nano /bwdata/env/global.override.env


echo "Starting Bitwarden..."
cd /opt/bitwarden
./bitwarden.sh start


echo "Listing Docker containers..."
docker ps


echo "Setup complete - you can access the console at http://$(hostname -I)"


echo "###########################"
echo "Setup Bitwarden : complete"
echo "###########################"
