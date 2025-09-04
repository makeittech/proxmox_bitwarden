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
usermod -aG docker root
usermod -aG docker vaultadmin
sudo mkdir /opt/bitwarden
sudo chmod -R 700 /opt/bitwarden
curl -Lso bitwarden.sh https://go.btwrdn.co/bw-sh && chmod 700 bitwarden.sh
./bitwarden.sh install


echo "Opening config file(s) for editing..."
nano /bwdata/env/global.override.env


echo "Starting Bitwarden..."
./bitwarden.sh start


echo "Listing Docker containers..."
docker ps


echo "Setup complete - you can access the console at http://$(hostname -I)"


echo "###########################"
echo "Setup Bitwarden : complete"
echo "###########################"
