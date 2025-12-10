# Nextcloud Docker Generator

Interactive shell script to deploy multi-tenant Nextcloud with Caddy for automatic HTTPS.

**[Deutsche Anleitung / German Guide](README.de.md)**

## Features

- Automatic HTTPS via Caddy (Let's Encrypt)
- PostgreSQL 15 database per instance
- Redis 7 caching per instance
- Nginx for PHP-FPM optimization
- Multiple Nextcloud instances support
- Isolated backend networks
- Auto-generated secure passwords

---

## Complete Setup Guide (Ubuntu 24.04 LTS)

This guide walks you through setting up a fresh Ubuntu 24.04 LTS server for Nextcloud hosting.

### 1. Initial Server Setup

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y curl wget git htop nano ufw
```

### 2. Configure Firewall

```bash
# Allow SSH, HTTP, and HTTPS
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Enable firewall
sudo ufw enable

# Verify status
sudo ufw status
```

### 3. Configure Secondary Disk with LVM

Most servers have a small OS disk and a larger data disk. We'll configure the data disk with LVM for flexibility.

```bash
# List available disks
lsblk

# Identify your secondary disk (e.g., /dev/sdb or /dev/vdb)
# WARNING: This will erase all data on the disk!

# Install LVM tools
sudo apt install -y lvm2

# Create physical volume (replace /dev/sdb with your disk)
sudo pvcreate /dev/sdb

# Create volume group named 'data-vg'
sudo vgcreate data-vg /dev/sdb

# Create logical volume using 100% of available space
sudo lvcreate -l 100%FREE -n data-lv data-vg

# Format with ext4
sudo mkfs.ext4 /dev/data-vg/data-lv

# Create mount point
sudo mkdir -p /srv

# Get UUID of the new volume
sudo blkid /dev/data-vg/data-lv

# Add to /etc/fstab for persistent mount (replace UUID with actual value)
echo "UUID=YOUR-UUID-HERE /srv ext4 defaults 0 2" | sudo tee -a /etc/fstab

# Mount the volume
sudo mount -a

# Verify mount
df -h /srv
```

### 4. Install Docker

```bash
# Install Docker using official script
curl -fsSL https://get.docker.com | sudo sh

# Add your user to docker group (logout/login required)
sudo usermod -aG docker $USER

# Enable Docker to start on boot
sudo systemctl enable docker

# Start Docker
sudo systemctl start docker

# Logout and login again, then verify
docker --version
docker ps
```

### 5. Move Docker Data to /srv

By default, Docker stores data in `/var/lib/docker`. We'll move it to `/srv` for more space.

```bash
# Stop Docker
sudo systemctl stop docker

# Create Docker directory on data disk
sudo mkdir -p /srv/docker

# Move existing Docker data (if any)
sudo rsync -avxP /var/lib/docker/ /srv/docker/

# Configure Docker to use new location
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "data-root": "/srv/docker"
}
EOF

# Remove old Docker data (optional, after verifying)
sudo rm -rf /var/lib/docker

# Start Docker
sudo systemctl start docker

# Verify new data location
docker info | grep "Docker Root Dir"
```

### 6. Configure DNS

Before running the script, ensure your domain(s) point to your server:

1. Go to your DNS provider
2. Create an A record for each Nextcloud instance:
   - `cloud.example.com` → `YOUR_SERVER_IP`
   - `files.example.com` → `YOUR_SERVER_IP`
3. Wait for DNS propagation (can take up to 24h, usually minutes)

Verify DNS:
```bash
dig +short cloud.example.com
curl -s ifconfig.me
# Both should show the same IP
```

### 7. Deploy Nextcloud

```bash
# Navigate to data disk
cd /srv

# Download and run the deployment script
curl -fsSL https://raw.githubusercontent.com/gstohl/nextcloud-docker-generator/main/deploy-nextcloud.sh -o deploy-nextcloud.sh
chmod +x deploy-nextcloud.sh
./deploy-nextcloud.sh
```

The script will prompt you for:
- **Project directory**: Where to store configs (e.g., `nextcloud`)
- **ACME email**: For Let's Encrypt certificate notifications
- **Number of instances**: How many Nextcloud sites
- **Domain per instance**: e.g., `cloud.example.com`
- **Admin username per instance**: Default is `admin`

### 8. Post-Installation

After deployment:

```bash
# Check container status
cd /srv/nextcloud  # or your project directory
./manage.sh status

# View logs
./manage.sh logs

# View Caddy logs (for SSL issues)
./manage.sh logs caddy
```

**Credentials** are saved in `credentials.txt` - save them securely and delete the file!

---

## Management Commands

```bash
./manage.sh status              # Check container status
./manage.sh logs [service]      # View logs
./manage.sh restart [service]   # Restart service
./manage.sh fix-permissions     # Fix file permissions
./manage.sh occ1 [command]      # Run occ on instance 1
```

## Troubleshooting

### SSL Certificate Issues
```bash
# Check Caddy logs
docker logs caddy

# Verify ports are open
curl -v http://your-domain.com
```

### 403 Forbidden Errors
```bash
./manage.sh fix-permissions
./manage.sh restart
```

### Check Disk Space
```bash
df -h /srv
docker system df
```

### Clean Up Docker
```bash
# Remove unused images and containers
docker system prune -a
```

## Backup

```bash
# Backup all data
cd /srv/nextcloud
docker compose stop
sudo tar -czvf /backup/nextcloud-$(date +%Y%m%d).tar.gz .
docker compose start
```

## License

MIT
