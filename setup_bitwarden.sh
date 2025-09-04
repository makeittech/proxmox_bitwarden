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

# Try multiple download URLs as fallbacks
DOWNLOAD_URLS=(
    "https://go.btwrdn.co/bw-sh"
    "https://func.bitwarden.com/api/dl/?app=self-host&platform=linux"
    "https://raw.githubusercontent.com/bitwarden/server/master/scripts/bitwarden.sh"
)

DOWNLOAD_SUCCESS=false
for url in "${DOWNLOAD_URLS[@]}"; do
    echo "Trying URL: $url"
    curl -Lso bitwarden.sh "$url"
    if [ $? -eq 0 ] && [ -s bitwarden.sh ]; then
        echo "Download successful from: $url"
        echo "File size: $(wc -c < bitwarden.sh) bytes"
        
        # Check if the file looks like a valid script
        if head -1 bitwarden.sh | grep -q "#!/bin/bash\|#!/usr/bin/env bash"; then
            echo "Valid script detected, setting permissions..."
            chmod 700 bitwarden.sh
            echo "First few lines of downloaded file:"
            head -5 bitwarden.sh
            DOWNLOAD_SUCCESS=true
            break
        else
            echo "Downloaded file doesn't appear to be a valid script:"
            head -5 bitwarden.sh
            echo "Trying next URL..."
        fi
    else
        echo "Failed to download from: $url"
    fi
done

if [ "$DOWNLOAD_SUCCESS" = true ]; then
    echo "Installing Bitwarden..."
    ./bitwarden.sh install
else
    echo "Failed to download Bitwarden installer from all URLs"
    echo "Using local fallback script..."
    
    # Create a local fallback script
    cat > bitwarden.sh << 'EOF'
#!/usr/bin/env bash
set -e

cat << "EOF_INNER"
 _     _ _                         _
| |__ (_) |___      ____ _ _ __ __| | ___ _ __
| '_ \| | __\ \ /\ / / _` | '__/ _` |/ _ \ '_ \
| |_) | | |_ \ V  V / (_| | | | (_| |  __/ | | |
|_.__/|_|\__| \_/\_/ \__,_|_|  \__,_|\___|_| |_|

EOF_INNER

cat << EOF_INNER
Open source password management solutions
Copyright 2015-$(date +'%Y'), 8bit Solutions LLC
https://bitwarden.com, https://github.com/bitwarden

===================================================

EOF_INNER

RED='\033[0;31m'
NC='\033[0m' # No Color

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}WARNING: This script is running as the root user!"
    echo -e "If you are running a standard deployment this script should be running as a dedicated Bitwarden User as per the documentation.${NC}"

    read -p "Do you still want to continue? (y/n): " choice

    # Check the user's choice
    case "$choice" in
        [Yy]|[Yy][Ee][Ss])
            echo -e "Continuing...."
            ;;
        *)
            exit 1
            ;;
    esac
fi

# Setup
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH="$DIR/$SCRIPT_NAME"
OUTPUT="$DIR/bwdata"
if [ $# -eq 2 ]
then
    OUTPUT=$2
fi

if docker compose &> /dev/null; then
    dccmd='docker compose'
elif command -v docker-compose &> /dev/null; then
    dccmd='docker-compose'
    echo "docker compose not found, falling back to docker-compose."
else
    echo "Error: Neither 'docker compose' nor 'docker-compose' commands were found. Please install Docker Compose." >&2
    exit 1
fi

SCRIPTS_DIR="$OUTPUT/scripts"
BITWARDEN_SCRIPT_URL="https://func.bitwarden.com/api/dl/?app=self-host&platform=linux"
RUN_SCRIPT_URL="https://func.bitwarden.com/api/dl/?app=self-host&platform=linux&variant=run"

# Please do not create pull requests modifying the version numbers.
COREVERSION="2024.12.1"
WEBVERSION="2024.12.1"
KEYCONNECTORVERSION="2024.8.0"

echo "bitwarden.sh version $COREVERSION"
docker --version
if [[ "$dccmd" == "docker compose" ]]; then
    $dccmd version
else
    $dccmd --version
fi

echo ""

# Functions
function downloadSelf() {
    if curl -L -s -w "http_code %{http_code}" -o $SCRIPT_PATH.1 $BITWARDEN_SCRIPT_URL | grep -q "^http_code 20[0-9]"
    then
        mv -f $SCRIPT_PATH.1 $SCRIPT_PATH
        chmod u+x $SCRIPT_PATH
    else
        rm -f $SCRIPT_PATH.1
    fi
}

function downloadRunFile() {
    if [ ! -d "$SCRIPTS_DIR" ]
    then
        mkdir $SCRIPTS_DIR
    fi

    local tmp_script=$(mktemp)
    run_file_status_code=$(curl -s -L -w "%{http_code}" -o $tmp_script $RUN_SCRIPT_URL)

    if echo "$run_file_status_code" | grep -q "^20[0-9]"
    then
        mv $tmp_script $SCRIPTS_DIR/run.sh
        chmod u+x $SCRIPTS_DIR/run.sh
        rm -f $SCRIPTS_DIR/install.sh
    else
        echo "Unable to download run script from $RUN_SCRIPT_URL. Received status code: $run_file_status_code"
        echo "http response:"
        cat $tmp_script
        rm -f $tmp_script
        exit 1
    fi
}

function checkOutputDirExists() {
    if [ ! -d "$OUTPUT" ]
    then
        echo "Cannot find a Bitwarden installation at $OUTPUT."
        exit 1
    fi
}

function checkOutputDirNotExists() {
    if [ -d "$OUTPUT/docker" ]
    then
        echo "Looks like Bitwarden is already installed at $OUTPUT."
        exit 1
    fi
}

function listCommands() {
cat << EOT
Available commands:

install
start
restart
stop
update
updatedb
updaterun
updateself
updateconf
uninstall
renewcert
rebuild
compresslogs
help

See more at https://bitwarden.com/help/article/install-on-premise/#script-commands-reference

EOT
}

# Commands
case $1 in
    "install")
        checkOutputDirNotExists
        mkdir -p $OUTPUT
        downloadRunFile
        $SCRIPTS_DIR/run.sh install $OUTPUT $COREVERSION $WEBVERSION $KEYCONNECTORVERSION
        ;;
    "start" | "restart")
        checkOutputDirExists
        $SCRIPTS_DIR/run.sh restart $OUTPUT $COREVERSION $WEBVERSION $KEYCONNECTORVERSION
        ;;
    "update")
        checkOutputDirExists
        downloadRunFile
        $SCRIPTS_DIR/run.sh update $OUTPUT $COREVERSION $WEBVERSION $KEYCONNECTORVERSION
        ;;
    "rebuild")
        checkOutputDirExists
        $SCRIPTS_DIR/run.sh rebuild $OUTPUT $COREVERSION $WEBVERSION $KEYCONNECTORVERSION
        ;;
    "updateconf")
        checkOutputDirExists
        $SCRIPTS_DIR/run.sh updateconf $OUTPUT $COREVERSION $WEBVERSION $KEYCONNECTORVERSION
        ;;
    "updatedb")
        checkOutputDirExists
        $SCRIPTS_DIR/run.sh updatedb $OUTPUT $COREVERSION $WEBVERSION $KEYCONNECTORVERSION
        ;;
    "stop")
        checkOutputDirExists
        $SCRIPTS_DIR/run.sh stop $OUTPUT $COREVERSION $WEBVERSION $KEYCONNECTORVERSION
        ;;
    "renewcert")
        checkOutputDirExists
        $SCRIPTS_DIR/run.sh renewcert $OUTPUT $COREVERSION $WEBVERSION $KEYCONNECTORVERSION
        ;;
    "updaterun")
        checkOutputDirExists
        downloadRunFile
        ;;
    "updateself")
        downloadSelf && echo "Updated self." && exit
        ;;
    "uninstall")
        checkOutputDirExists
        $SCRIPTS_DIR/run.sh uninstall $OUTPUT
        ;;
    "compresslogs")
        checkOutputDirExists
        compressLogs $OUTPUT $2 $3
        ;;
    "help")
        listCommands
        ;;
    *)
        echo "No command found."
        echo
        listCommands
esac
EOF
    
    chmod 700 bitwarden.sh
    echo "Local fallback script created successfully"
    echo "Installing Bitwarden with fallback script..."
    ./bitwarden.sh install
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
