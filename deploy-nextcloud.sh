#!/bin/bash

# ============================================================================
# Nextcloud Multi-tenant Deployment with Caddy
# Interactive installer - just run and answer the prompts!
# ============================================================================

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Banner
clear
echo -e "${CYAN}============================================================================${NC}"
echo -e "${CYAN}     NEXTCLOUD WITH CADDY - INTERACTIVE DEPLOYMENT${NC}"
echo -e "${CYAN}============================================================================${NC}"
echo ""
echo "This script will deploy Nextcloud with:"
echo "  ✓ Automatic HTTPS via Caddy"
echo "  ✓ PostgreSQL database"
echo "  ✓ Redis caching"
echo "  ✓ Nginx for PHP-FPM"
echo "  ✓ Multiple instances support"
echo ""
echo -e "${CYAN}============================================================================${NC}"
echo ""

# Check prerequisites
print_info "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed"
    echo "Install with: curl -fsSL https://get.docker.com | sh"
    exit 1
fi

if ! docker ps >/dev/null 2>&1; then
    print_error "Cannot connect to Docker"
    echo "Add user to docker group: sudo usermod -aG docker $USER && newgrp docker"
    exit 1
fi

print_success "Prerequisites met"
echo ""

# Gather configuration
echo -e "${CYAN}--- Configuration ---${NC}"
echo ""

read -p "Project directory name [nextcloud-caddy]: " PROJECT_DIR
PROJECT_DIR=${PROJECT_DIR:-nextcloud-caddy}

read -p "Let's Encrypt email: " ACME_EMAIL
while [[ -z "$ACME_EMAIL" || ! "$ACME_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; do
    print_warning "Please enter a valid email address"
    read -p "Let's Encrypt email: " ACME_EMAIL
done

read -p "How many Nextcloud instances? [1]: " NUM_INSTANCES
NUM_INSTANCES=${NUM_INSTANCES:-1}

# Validate number
if ! [[ "$NUM_INSTANCES" =~ ^[0-9]+$ ]] || [ "$NUM_INSTANCES" -lt 1 ]; then
    print_error "Invalid number of instances"
    exit 1
fi

echo ""
echo -e "${CYAN}--- Instance Configuration ---${NC}"

declare -a DOMAINS
declare -a ADMIN_USERS

for i in $(seq 1 $NUM_INSTANCES); do
    echo ""
    echo -e "${YELLOW}Instance $i:${NC}"

    read -p "  Domain (e.g., cloud.example.com): " domain
    while [[ -z "$domain" ]]; do
        print_warning "Domain cannot be empty"
        read -p "  Domain (e.g., cloud.example.com): " domain
    done
    DOMAINS+=("$domain")

    read -p "  Admin username [admin]: " admin_user
    admin_user=${admin_user:-admin}
    ADMIN_USERS+=("$admin_user")
done

# Confirm configuration
echo ""
echo -e "${CYAN}============================================================================${NC}"
echo -e "${CYAN}                    CONFIGURATION SUMMARY${NC}"
echo -e "${CYAN}============================================================================${NC}"
echo ""
echo "  Project Directory: $PROJECT_DIR"
echo "  ACME Email: $ACME_EMAIL"
echo "  Instances: $NUM_INSTANCES"
echo ""
for i in $(seq 0 $((NUM_INSTANCES - 1))); do
    echo "  Instance $((i + 1)):"
    echo "    Domain: ${DOMAINS[$i]}"
    echo "    Admin: ${ADMIN_USERS[$i]}"
done
echo ""
echo -e "${CYAN}============================================================================${NC}"
echo ""

read -p "Proceed with deployment? [Y/n]: " confirm
if [[ "$confirm" =~ ^[Nn] ]]; then
    print_info "Deployment cancelled"
    exit 0
fi

# Check DNS
echo ""
print_info "Checking DNS configuration..."
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")
print_info "Server IP: ${PUBLIC_IP}"

for domain in "${DOMAINS[@]}"; do
    DOMAIN_IP=$(dig +short "$domain" 2>/dev/null | tail -n1)
    if [ "$DOMAIN_IP" = "$PUBLIC_IP" ]; then
        print_success "$domain → $DOMAIN_IP ✓"
    else
        print_warning "$domain → $DOMAIN_IP (should be $PUBLIC_IP)"
    fi
done

# Create directory structure
echo ""
print_info "Creating directory structure..."
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
mkdir -p caddy/{data,config}
mkdir -p nginx
mkdir -p backups

# Generate secure passwords
print_info "Generating secure passwords..."
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-24
}

declare -a DB_PASSWORDS
declare -a REDIS_PASSWORDS
declare -a NC_ADMIN_PASSWORDS

for i in $(seq 1 $NUM_INSTANCES); do
    DB_PASSWORDS+=("$(generate_password)")
    REDIS_PASSWORDS+=("$(generate_password)")
    NC_ADMIN_PASSWORDS+=("$(generate_password)")
done

# Create .env file
print_info "Creating environment configuration..."
cat > .env << EOF
# Generated: $(date)
# Nextcloud Multi-tenant Deployment
EOF

for i in $(seq 0 $((NUM_INSTANCES - 1))); do
    n=$((i + 1))
    cat >> .env << EOF
DB${n}_PASSWORD=${DB_PASSWORDS[$i]}
REDIS${n}_PASSWORD=${REDIS_PASSWORDS[$i]}
NC${n}_ADMIN_USER=${ADMIN_USERS[$i]}
NC${n}_ADMIN_PASSWORD=${NC_ADMIN_PASSWORDS[$i]}
EOF
done

echo "ACME_EMAIL=$ACME_EMAIL" >> .env
chmod 600 .env

# Create Caddyfile
print_info "Creating Caddyfile..."
cat > caddy/Caddyfile << EOF
{
    email $ACME_EMAIL
}

EOF

for i in $(seq 0 $((NUM_INSTANCES - 1))); do
    n=$((i + 1))
    cat >> caddy/Caddyfile << EOF
${DOMAINS[$i]} {
    reverse_proxy nginx${n}:80

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        X-Robots-Tag "noindex, nofollow"
        -X-Powered-By
    }
}

EOF
done

# Create nginx configuration template
print_info "Creating nginx configurations..."

cat > nginx/nextcloud.conf.template << 'NGINX_TEMPLATE'
user nginx;
worker_processes auto;

events {
    worker_connections 2048;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    client_max_body_size 10G;
    client_body_buffer_size 512k;
    client_body_timeout 300s;
    fastcgi_buffers 64 4K;

    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_types text/css text/javascript text/xml text/plain application/javascript application/json application/xml;

    upstream php-handler {
        server NEXTCLOUD_APP:9000;
    }

    server {
        listen 80;
        server_name _;

        root /var/www/html;

        add_header X-Content-Type-Options nosniff always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Robots-Tag "noindex, nofollow" always;
        add_header X-Download-Options noopen always;
        add_header X-Permitted-Cross-Domain-Policies none always;
        add_header Referrer-Policy no-referrer always;
        add_header X-XSS-Protection "1; mode=block" always;

        fastcgi_hide_header X-Powered-By;

        index index.php index.html /index.php$request_uri;

        location = / {
            if ( $http_user_agent ~ ^DavClnt ) {
                return 302 /remote.php/webdav/$is_args$args;
            }
        }

        location = /robots.txt {
            allow all;
            log_not_found off;
            access_log off;
        }

        location ^~ /.well-known {
            location = /.well-known/carddav   { return 301 /remote.php/dav/; }
            location = /.well-known/caldav    { return 301 /remote.php/dav/; }
            location /.well-known/acme-challenge    { try_files $uri $uri/ =404; }
            location /.well-known/pki-validation    { try_files $uri $uri/ =404; }
            return 301 /index.php$request_uri;
        }

        location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/)  { return 404; }
        location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console)                { return 404; }

        location ~ \.php(?:$|/) {
            rewrite ^/(?!index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|oc[sm]-provider\/.+|.+\/richdocumentscode\/proxy) /index.php$request_uri;

            fastcgi_split_path_info ^(.+?\.php)(/.*)$;
            set $path_info $fastcgi_path_info;

            try_files $fastcgi_script_name =404;

            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_param PATH_INFO $path_info;
            fastcgi_param HTTPS on;

            fastcgi_param modHeadersAvailable true;
            fastcgi_param front_controller_active true;
            fastcgi_pass php-handler;

            fastcgi_intercept_errors on;
            fastcgi_request_buffering off;
            fastcgi_max_temp_file_size 0;
        }

        location ~ \.(?:css|js|mjs|svg|gif|png|jpg|ico|wasm|tflite|map|ogg|flac)$ {
            try_files $uri /index.php$request_uri;
            add_header Cache-Control "public, max-age=15778463";
            access_log off;
        }

        location ~ \.woff2?$ {
            try_files $uri /index.php$request_uri;
            expires 7d;
            access_log off;
        }

        location /remote {
            return 301 /remote.php$request_uri;
        }

        location / {
            try_files $uri $uri/ /index.php$request_uri;
        }
    }
}
NGINX_TEMPLATE

for i in $(seq 1 $NUM_INSTANCES); do
    sed "s/NEXTCLOUD_APP/nextcloud${i}-app/g" nginx/nextcloud.conf.template > "nginx/nginx${i}.conf"
done

rm nginx/nextcloud.conf.template
print_success "Nginx configurations created"

# Create docker-compose.yml
print_info "Creating docker-compose.yml..."

cat > docker-compose.yml << 'EOF'
services:
  caddy:
    image: caddy:alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ./caddy/data:/data
      - ./caddy/config:/config
    networks:
      - proxy-tier
    depends_on:
EOF

# Add nginx dependencies
for i in $(seq 1 $NUM_INSTANCES); do
    echo "      - nginx${i}" >> docker-compose.yml
done

# Add services for each instance
for i in $(seq 0 $((NUM_INSTANCES - 1))); do
    n=$((i + 1))
    domain="${DOMAINS[$i]}"

    cat >> docker-compose.yml << EOF

  # Nextcloud Instance ${n} - ${domain}
  nextcloud${n}:
    image: nextcloud:fpm-alpine
    container_name: nextcloud${n}-app
    restart: unless-stopped
    environment:
      - POSTGRES_HOST=db${n}
      - POSTGRES_DB=nextcloud${n}
      - POSTGRES_USER=nextcloud${n}
      - POSTGRES_PASSWORD=\${DB${n}_PASSWORD}
      - REDIS_HOST=redis${n}
      - REDIS_HOST_PASSWORD=\${REDIS${n}_PASSWORD}
      - NEXTCLOUD_ADMIN_USER=\${NC${n}_ADMIN_USER}
      - NEXTCLOUD_ADMIN_PASSWORD=\${NC${n}_ADMIN_PASSWORD}
      - NEXTCLOUD_TRUSTED_DOMAINS=${domain}
      - OVERWRITEPROTOCOL=https
      - OVERWRITEHOST=${domain}
      - TRUSTED_PROXIES=caddy nginx${n}
      - PHP_MEMORY_LIMIT=1G
      - PHP_UPLOAD_LIMIT=10G
    volumes:
      - nc${n}_html:/var/www/html
    networks:
      - backend${n}
      - proxy-tier
    depends_on:
      - db${n}
      - redis${n}

  nginx${n}:
    image: nginx:alpine
    container_name: nginx${n}
    restart: unless-stopped
    volumes:
      - ./nginx/nginx${n}.conf:/etc/nginx/nginx.conf:ro
      - nc${n}_html:/var/www/html:ro
    networks:
      - backend${n}
      - proxy-tier
    depends_on:
      - nextcloud${n}

  nextcloud${n}-cron:
    image: nextcloud:fpm-alpine
    container_name: nextcloud${n}-cron
    restart: unless-stopped
    entrypoint: /cron.sh
    volumes:
      - nc${n}_html:/var/www/html
    networks:
      - backend${n}
    depends_on:
      - db${n}
      - redis${n}

  db${n}:
    image: postgres:15-alpine
    container_name: nextcloud${n}-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: nextcloud${n}
      POSTGRES_USER: nextcloud${n}
      POSTGRES_PASSWORD: \${DB${n}_PASSWORD}
    volumes:
      - db${n}_data:/var/lib/postgresql/data
    networks:
      - backend${n}

  redis${n}:
    image: redis:7-alpine
    container_name: nextcloud${n}-redis
    restart: unless-stopped
    command: redis-server --requirepass \${REDIS${n}_PASSWORD}
    volumes:
      - redis${n}_data:/data
    networks:
      - backend${n}
EOF
done

# Add volumes
echo "" >> docker-compose.yml
echo "volumes:" >> docker-compose.yml
for i in $(seq 1 $NUM_INSTANCES); do
    echo "  nc${i}_html:" >> docker-compose.yml
    echo "  db${i}_data:" >> docker-compose.yml
    echo "  redis${i}_data:" >> docker-compose.yml
done

# Add networks
echo "" >> docker-compose.yml
echo "networks:" >> docker-compose.yml
echo "  proxy-tier:" >> docker-compose.yml
for i in $(seq 1 $NUM_INSTANCES); do
    echo "  backend${i}:" >> docker-compose.yml
    echo "    internal: true" >> docker-compose.yml
done

print_success "docker-compose.yml created"

# Create networks
print_info "Creating Docker networks..."
docker network create proxy-tier 2>/dev/null || true
for i in $(seq 1 $NUM_INSTANCES); do
    docker network create "backend${i}" 2>/dev/null || true
done

# Deploy
print_info "Starting deployment..."
docker compose up -d

# Wait for services
print_info "Waiting for services to initialize (30 seconds)..."
sleep 30

# Fix permissions
print_info "Fixing permissions..."
for i in $(seq 1 $NUM_INSTANCES); do
    docker exec "nextcloud${i}-app" chown -R www-data:www-data /var/www/html 2>/dev/null || true
done

# Configure Nextcloud
print_info "Configuring Nextcloud settings..."
for i in $(seq 0 $((NUM_INSTANCES - 1))); do
    n=$((i + 1))
    domain="${DOMAINS[$i]}"
    docker exec -u www-data "nextcloud${n}-app" php occ config:system:set trusted_domains 0 --value="$domain" 2>/dev/null || true
    docker exec -u www-data "nextcloud${n}-app" php occ config:system:set trusted_proxies 0 --value="caddy" 2>/dev/null || true
    docker exec -u www-data "nextcloud${n}-app" php occ config:system:set trusted_proxies 1 --value="nginx${n}" 2>/dev/null || true
    docker exec -u www-data "nextcloud${n}-app" php occ config:system:set overwrite.cli.url --value="https://$domain" 2>/dev/null || true
    docker exec -u www-data "nextcloud${n}-app" php occ config:system:set overwriteprotocol --value="https" 2>/dev/null || true
done

# Save credentials
print_info "Saving credentials..."
cat > credentials.txt << EOF
============================================================================
                 NEXTCLOUD WITH CADDY - CREDENTIALS
============================================================================
Generated: $(date)

EOF

for i in $(seq 0 $((NUM_INSTANCES - 1))); do
    n=$((i + 1))
    cat >> credentials.txt << EOF
${DOMAINS[$i]}
--------------------------
URL: https://${DOMAINS[$i]}
Admin User: ${ADMIN_USERS[$i]}
Admin Password: ${NC_ADMIN_PASSWORDS[$i]}
Database Password: ${DB_PASSWORDS[$i]}
Redis Password: ${REDIS_PASSWORDS[$i]}

EOF
done

cat >> credentials.txt << EOF
============================================================================
IMPORTANT: Save these credentials and delete this file!
============================================================================
EOF

chmod 600 credentials.txt

# Check status
echo ""
print_info "Checking service status..."
SERVICES_OK=true

check_service() {
    if docker ps | grep -q "$1"; then
        print_success "$1 running"
    else
        print_error "$1 not running"
        SERVICES_OK=false
    fi
}

check_service "caddy"
for i in $(seq 1 $NUM_INSTANCES); do
    check_service "nginx${i}"
    check_service "nextcloud${i}-app"
    check_service "nextcloud${i}-db"
    check_service "nextcloud${i}-redis"
done

# Create management script
print_info "Creating management script..."
cat > manage.sh << 'MANAGE_EOF'
#!/bin/bash
case "$1" in
    logs)
        docker compose logs -f ${2}
        ;;
    restart)
        docker compose restart ${2}
        ;;
    status)
        docker compose ps
        ;;
    fix-permissions)
MANAGE_EOF

for i in $(seq 1 $NUM_INSTANCES); do
    echo "        docker exec nextcloud${i}-app chown -R www-data:www-data /var/www/html" >> manage.sh
done

cat >> manage.sh << 'MANAGE_EOF'
        ;;
MANAGE_EOF

for i in $(seq 1 $NUM_INSTANCES); do
    cat >> manage.sh << EOF
    occ${i})
        docker exec -u www-data nextcloud${i}-app php occ \${@:2}
        ;;
EOF
done

# Build usage string
OCC_USAGE=""
for i in $(seq 1 $NUM_INSTANCES); do
    OCC_USAGE="${OCC_USAGE}occ${i}|"
done
OCC_USAGE=${OCC_USAGE%|}

cat >> manage.sh << EOF
    *)
        echo "Usage: \$0 {logs|restart|status|fix-permissions|${OCC_USAGE}} [args]"
        ;;
esac
EOF

chmod +x manage.sh

# Final output
echo ""
echo -e "${GREEN}============================================================================${NC}"
if [ "$SERVICES_OK" = true ]; then
    echo -e "${GREEN}           DEPLOYMENT COMPLETE!${NC}"
else
    echo -e "${YELLOW}           DEPLOYMENT COMPLETE WITH WARNINGS${NC}"
fi
echo -e "${GREEN}============================================================================${NC}"
echo ""
echo "Caddy will automatically obtain SSL certificates on first access!"
echo ""
echo "Access your Nextcloud instances:"
for domain in "${DOMAINS[@]}"; do
    echo -e "  🔒 ${GREEN}https://${domain}${NC}"
done
echo ""
echo -e "${YELLOW}Credentials saved to: credentials.txt${NC}"
echo -e "${RED}Delete credentials.txt after saving passwords!${NC}"
echo ""
echo "Management commands:"
echo "  ./manage.sh status              - Check status"
echo "  ./manage.sh logs [service]      - View logs"
echo "  ./manage.sh restart [service]   - Restart service"
echo "  ./manage.sh fix-permissions     - Fix file permissions"
for i in $(seq 1 $NUM_INSTANCES); do
    echo "  ./manage.sh occ${i} [command]      - Run occ on instance ${i}"
done
echo ""
echo "If you get 403 errors, run:"
echo "  ./manage.sh fix-permissions"
echo "  ./manage.sh restart"
echo ""
echo -e "${GREEN}============================================================================${NC}"
