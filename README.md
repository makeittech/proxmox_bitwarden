# Bitwarden on ProxMox

<p align="center">
    <img height="200" alt="Bitwarden Logo" src="img/logo_bitwarden.png">
    <img height="200" alt="ProxMox Logo" src="img/logo_proxmox.png">
</p>

Create a [ProxMox](https://www.proxmox.com/en/) LXC container running Ubuntu and install [Bitwarden](https://bitwarden.com/).

Tested on ProxMox v7 & Bitwarden 2022.12.0

## Usage

SSH to your ProxMox server as a privileged user and run...

```shell
bash -c "$(wget --no-cache -qLO - https://raw.githubusercontent.com/makeittech/proxmox_bitwarden/refs/heads/master/setup.sh"
```

## Installation Questions

- (!) Enter the domain name for your Bitwarden instance (ex. bitwarden.example.com):
...enter your domain...

- (!) Do you want to use Let's Encrypt to generate a free SSL certificate? (y/n):
`n`

- (!) Enter the database name for your Bitwarden instance (ex. vault):
...Just hit ENTER...

- (!) Enter your installation id (get at https://bitwarden.com/host):
...enter your id...

- (!) Enter your installation key:
...enter your key...

- (!) Do you have a SSL certificate to use? (y/n):
`n`

When `/bwdata/env/global.override.env` is opened for editing, enter SMTP details for email.

## Hacks & Troubleshooting

### Storage Error: "storage does not support container directories"

If you encounter the error `storage 'local' does not support container directories` during setup, this means the Proxmox storage doesn't have container support enabled.

**Quick Fix:**
```shell
./fix_storage_containers.sh local
```
(Replace `local` with your storage name)

**Manual Fix:**
1. Open Proxmox web interface
2. Go to Datacenter > Storage
3. Click on your storage (e.g., `local`)
4. In the 'Content' section, check the 'Container' checkbox
5. Click 'OK' to save
6. Run the setup script again

### Changing Domain Name

To change the domain name...

```shell
cd /
./bitwarden.sh stop
# replace instances of your domain name in these files... 
nano bwdata/config.yml
nano bwdata/env/global.override.env
nano bwdata/nginx/default.conf
./bitwarden.sh start
```

## Ideas/Reference

- [Install and Deploy - Linux](https://bitwarden.com/help/install-on-premise-linux/)
- [Hosting FAQs](https://bitwarden.com/help/hosting-faqs/)
- [How to Set Up End-to-End CloudFlare SSL Encryption](https://adamtheautomator.com/cloudflare-ssl/)
- [How to self host Vaultwarden/Bitwarden without exposing it publicly?](https://www.reddit.com/r/selfhosted/comments/xftv80/how_to_self_host_vaultwardenbitwarden_without/)
- [Running a private vaultwarden instance with Let's Encrypt certs](https://github.com/dani-garcia/vaultwarden/wiki/Running-a-private-vaultwarden-instance-with-Let%27s-Encrypt-certs)
