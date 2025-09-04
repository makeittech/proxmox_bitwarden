# Bitwarden on Proxmox

<p align="center">
    <img height="200" alt="Bitwarden Logo" src="img/logo_bitwarden.png">
    <img height="200" alt="Proxmox Logo" src="img/logo_proxmox.png">
</p>

Create a [Proxmox](https://www.proxmox.com/en/) LXC container running Ubuntu and install [Bitwarden](https://bitwarden.com/) using the proven community scripts approach.

**Tested on:** Proxmox VE 8.x & 9.x with Bitwarden Self-Hosted

## Features

- ✅ **Automated container creation** using Proxmox community scripts
- ✅ **Ubuntu 22.04 LTS** container with Docker support
- ✅ **Automatic Bitwarden installation** with self-hosted setup
- ✅ **Storage auto-detection** and template management
- ✅ **Network configuration** with DHCP or static IP support
- ✅ **Clean, reliable setup** based on proven community scripts

## Quick Start

### Prerequisites

- Proxmox VE 8.x or 9.x
- Root access to Proxmox host
- At least 2GB RAM and 8GB storage available

### Installation

SSH to your Proxmox server as root and run:

```bash
bash -c "$(wget --no-cache --no-cookies --tries=1 --timeout=30 --header='Cache-Control: no-cache, no-store, must-revalidate' --header='Pragma: no-cache' --header='Expires: 0' -qO- "https://raw.githubusercontent.com/makeittech/proxmox_bitwarden/master/setup.sh?v=$(date +%s)")"
```

### What Happens During Installation

1. **Container Creation**: Creates an Ubuntu 22.04 LXC container
2. **OS Setup**: Updates system and installs required packages
3. **Docker Installation**: Installs Docker and Docker Compose
4. **Bitwarden Setup**: Downloads and configures Bitwarden self-hosted
5. **Final Configuration**: Restarts container and provides access information

## Configuration Options

The script uses the community scripts interface and allows you to configure:

- **Container ID**: Auto-generated or custom
- **Hostname**: Defaults to "bitwarden"
- **Password**: Container root password
- **Network**: DHCP or static IP configuration
- **Storage**: Automatic detection of available storage
- **Resources**: CPU cores, RAM, and disk space

## Default Settings

- **Container OS**: Ubuntu 22.04 LTS
- **CPU Cores**: 2
- **RAM**: 4GB
- **Disk Space**: 8GB
- **Container Type**: Unprivileged (recommended)
- **Network**: DHCP (auto-detected)

## Access Your Bitwarden Instance

After installation completes, you'll see:

```
✔️ Container and app setup complete!
Container ID: [ID]
Hostname: bitwarden
Access Bitwarden at: http://[CONTAINER_IP]:8080
```

### Initial Bitwarden Setup

1. **Access the web interface** at `http://[CONTAINER_IP]:8080`
2. **Create your admin account** (first user becomes admin)
3. **Configure your organization** and settings
4. **Set up SSL** (recommended for production use)

### SSH Access

- **Username**: `root`
- **Password**: The password you set during container creation
- **Command**: `ssh root@[CONTAINER_IP]`

## Troubleshooting

### Container Creation Issues

If you encounter container creation errors:

1. **Check storage space**: Ensure at least 8GB free space
2. **Verify storage configuration**: Storage must support containers
3. **Check Proxmox version**: Ensure you're running 8.x or 9.x

### Storage Configuration

If you get "storage does not support container directories":

**Manual Fix:**
1. Open Proxmox web interface
2. Go to Datacenter > Storage
3. Click on your storage
4. Check the 'Container' checkbox in Content section
5. Click 'OK' to save

### Network Issues

If the container can't access the internet:

1. **Check bridge configuration**: Ensure vmbr0 is properly configured
2. **Verify firewall rules**: Check Proxmox firewall settings
3. **Test connectivity**: Use `pct exec [CTID] ping 8.8.8.8`

### Bitwarden Access Issues

If you can't access Bitwarden:

1. **Check container status**: `pct status [CTID]`
2. **Verify services**: `pct exec [CTID] docker ps`
3. **Check logs**: `pct exec [CTID] docker logs bitwarden`

## Advanced Configuration

### Custom Resource Allocation

You can modify the default resources by setting environment variables:

```bash
var_cpu=4 var_ram=8192 var_disk=100 bash -c "$(wget ...)"
```

### Static IP Configuration

The script will prompt for network configuration. For static IP:

1. Choose "static" when prompted
2. Enter your desired IP address
3. Set subnet mask (default: 24)
4. Configure gateway

### SSL/HTTPS Setup

For production use, set up SSL:

1. **Domain setup**: Configure DNS to point to your container IP
2. **SSL certificate**: Use Let's Encrypt or your own certificate
3. **Reverse proxy**: Consider using Traefik or Nginx Proxy Manager

## Maintenance

### Updating Bitwarden

```bash
pct exec [CTID] -- bash -c "cd /opt/bitwarden && ./bitwarden.sh updateself && ./bitwarden.sh update"
```

### Container Management

```bash
# Start container
pct start [CTID]

# Stop container
pct stop [CTID]

# Access container shell
pct exec [CTID] -- bash

# View container status
pct status [CTID]
```

### Backup

```bash
# Create container backup
vzdump [CTID] --storage [backup_storage]

# Backup Bitwarden data
pct exec [CTID] -- bash -c "cd /opt/bitwarden && ./bitwarden.sh backup"
```

## Security Considerations

- **Use unprivileged containers** (default)
- **Set up SSL/TLS** for production use
- **Configure firewall rules** appropriately
- **Regular updates** for both Proxmox and Bitwarden
- **Strong passwords** for all accounts
- **Backup regularly** your Bitwarden data

## Support

- **Issues**: [GitHub Issues](https://github.com/makeittech/proxmox_bitwarden/issues)
- **Bitwarden Documentation**: [Self-Hosted Guide](https://bitwarden.com/help/install-on-premise-linux/)
- **Proxmox Documentation**: [LXC Containers](https://pve.proxmox.com/wiki/Linux_Container)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built using [Proxmox Community Scripts](https://github.com/community-scripts/ProxmoxVE) framework
- Based on the proven AdGuard script approach
- Uses official [Bitwarden Self-Hosted](https://bitwarden.com/help/install-on-premise-linux/) installation