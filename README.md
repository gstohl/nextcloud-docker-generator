# Nextcloud Docker Generator

Interactive shell script to deploy multi-tenant Nextcloud with Caddy for automatic HTTPS.

## Features

- Automatic HTTPS via Caddy (Let's Encrypt)
- PostgreSQL 15 database per instance
- Redis 7 caching per instance
- Nginx for PHP-FPM optimization
- Multiple Nextcloud instances support
- Isolated backend networks
- Auto-generated secure passwords

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/gstohl/nextcloud-docker-generator/main/deploy-nextcloud.sh | bash
```

Or download and run:

```bash
wget https://raw.githubusercontent.com/gstohl/nextcloud-docker-generator/main/deploy-nextcloud.sh
chmod +x deploy-nextcloud.sh
./deploy-nextcloud.sh
```

## Requirements

- Linux server with Docker installed
- Ports 80 and 443 open
- Domain(s) pointing to your server

## What it does

1. Prompts for configuration (domains, email, admin users)
2. Creates directory structure
3. Generates secure passwords
4. Creates Caddyfile, nginx configs, docker-compose.yml
5. Starts all containers
6. Saves credentials to `credentials.txt`

## Management

After deployment, use the generated `manage.sh` script:

```bash
./manage.sh status              # Check container status
./manage.sh logs [service]      # View logs
./manage.sh restart [service]   # Restart service
./manage.sh fix-permissions     # Fix file permissions
./manage.sh occ1 [command]      # Run occ on instance 1
```

## License

MIT
