export interface NextcloudInstance {
  domain: string;
  adminUser: string;
}

export interface Config {
  projectDir: string;
  acmeEmail: string;
  instances: NextcloudInstance[];
}

export function generateScript(config: Config): string {
  const { projectDir, acmeEmail, instances } = config;

  // Generate domain variables
  const domainVars = instances
    .map((inst, i) => `DOMAIN${i + 1}="${inst.domain}"`)
    .join("\n");

  // Generate domain list for DNS check
  const domainList = instances.map((_, i) => `$DOMAIN${i + 1}`).join(" ");

  // Generate banner domains
  const bannerDomains = instances
    .map(
      (inst, i) =>
        `echo "  \u2022 \${GREEN}\${DOMAIN${i + 1}}\${NC} - Nextcloud Instance ${i + 1}"`
    )
    .join("\n");

  // Generate password variables
  const passwordGeneration = instances
    .map(
      (_, i) => `DB${i + 1}_PASSWORD=$(generate_password)
REDIS${i + 1}_PASSWORD=$(generate_password)
NC${i + 1}_ADMIN_PASSWORD=$(generate_password)`
    )
    .join("\n");

  // Generate .env content
  const envContent = instances
    .map(
      (inst, i) => `DB${i + 1}_PASSWORD=\${DB${i + 1}_PASSWORD}
REDIS${i + 1}_PASSWORD=\${REDIS${i + 1}_PASSWORD}
NC${i + 1}_ADMIN_USER=${inst.adminUser}
NC${i + 1}_ADMIN_PASSWORD=\${NC${i + 1}_ADMIN_PASSWORD}`
    )
    .join("\n");

  // Generate Caddyfile entries
  const caddyfileEntries = instances
    .map(
      (_, i) => `\${DOMAIN${i + 1}} {
    reverse_proxy nginx${i + 1}:80

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        X-Robots-Tag "noindex, nofollow"
        -X-Powered-By
    }
}`
    )
    .join("\n\n");

  // Generate docker-compose services
  const generateNextcloudServices = () => {
    return instances
      .map((inst, i) => {
        const num = i + 1;
        return `  # Nextcloud Instance ${num} - ${inst.domain}
  nextcloud${num}:
    image: nextcloud:fpm-alpine
    container_name: nextcloud${num}-app
    restart: unless-stopped
    environment:
      - POSTGRES_HOST=db${num}
      - POSTGRES_DB=nextcloud${num}
      - POSTGRES_USER=nextcloud${num}
      - POSTGRES_PASSWORD=\${DB${num}_PASSWORD}
      - REDIS_HOST=redis${num}
      - REDIS_HOST_PASSWORD=\${REDIS${num}_PASSWORD}
      - NEXTCLOUD_ADMIN_USER=\${NC${num}_ADMIN_USER}
      - NEXTCLOUD_ADMIN_PASSWORD=\${NC${num}_ADMIN_PASSWORD}
      - NEXTCLOUD_TRUSTED_DOMAINS=${inst.domain}
      - OVERWRITEPROTOCOL=https
      - OVERWRITEHOST=${inst.domain}
      - TRUSTED_PROXIES=caddy nginx${num}
      - PHP_MEMORY_LIMIT=1G
      - PHP_UPLOAD_LIMIT=10G
    volumes:
      - nc${num}_html:/var/www/html
    networks:
      - backend${num}
      - proxy-tier
    depends_on:
      - db${num}
      - redis${num}

  nginx${num}:
    image: nginx:alpine
    container_name: nginx${num}
    restart: unless-stopped
    volumes:
      - ./nginx/nginx${num}.conf:/etc/nginx/nginx.conf:ro
      - nc${num}_html:/var/www/html:ro
    networks:
      - backend${num}
      - proxy-tier
    depends_on:
      - nextcloud${num}

  nextcloud${num}-cron:
    image: nextcloud:fpm-alpine
    container_name: nextcloud${num}-cron
    restart: unless-stopped
    entrypoint: /cron.sh
    volumes:
      - nc${num}_html:/var/www/html
    networks:
      - backend${num}
    depends_on:
      - db${num}
      - redis${num}

  db${num}:
    image: postgres:15-alpine
    container_name: nextcloud${num}-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: nextcloud${num}
      POSTGRES_USER: nextcloud${num}
      POSTGRES_PASSWORD: \${DB${num}_PASSWORD}
    volumes:
      - db${num}_data:/var/lib/postgresql/data
    networks:
      - backend${num}

  redis${num}:
    image: redis:7-alpine
    container_name: nextcloud${num}-redis
    restart: unless-stopped
    command: redis-server --requirepass \${REDIS${num}_PASSWORD}
    volumes:
      - redis${num}_data:/data
    networks:
      - backend${num}`;
      })
      .join("\n\n");
  };

  // Generate caddy depends_on
  const caddyDependsOn = instances.map((_, i) => `nginx${i + 1}`).join("\n      - ");

  // Generate volumes
  const volumes = instances
    .map(
      (_, i) => `  nc${i + 1}_html:
  db${i + 1}_data:
  redis${i + 1}_data:`
    )
    .join("\n");

  // Generate networks
  const networks = instances.map((_, i) => `  backend${i + 1}:\n    internal: true`).join("\n");

  // Generate nginx configs creation
  const nginxConfigCreation = instances
    .map(
      (_, i) =>
        `sed 's/NEXTCLOUD_APP/nextcloud${i + 1}-app/g' nginx/nextcloud.conf.template > nginx/nginx${i + 1}.conf`
    )
    .join("\n");

  // Generate docker network creation
  const networkCreation = instances
    .map((_, i) => `docker network create backend${i + 1} 2>/dev/null || true`)
    .join("\n");

  // Generate permission fixes
  const permissionFixes = instances
    .map(
      (_, i) =>
        `docker exec nextcloud${i + 1}-app chown -R www-data:www-data /var/www/html 2>/dev/null || true`
    )
    .join("\n");

  // Generate initial setup
  const initialSetup = instances
    .map(
      (_, i) =>
        `docker exec -u www-data nextcloud${i + 1}-app php occ maintenance:install --admin-user admin --admin-pass "\${NC${i + 1}_ADMIN_PASSWORD}" 2>/dev/null || true`
    )
    .join("\n");

  // Generate Nextcloud configuration
  const nextcloudConfig = instances
    .map(
      (inst, i) => `docker exec -u www-data nextcloud${i + 1}-app php occ config:system:set trusted_domains 0 --value="${inst.domain}" 2>/dev/null || true
docker exec -u www-data nextcloud${i + 1}-app php occ config:system:set trusted_proxies 0 --value="caddy" 2>/dev/null || true
docker exec -u www-data nextcloud${i + 1}-app php occ config:system:set trusted_proxies 1 --value="nginx${i + 1}" 2>/dev/null || true
docker exec -u www-data nextcloud${i + 1}-app php occ config:system:set overwrite.cli.url --value="https://${inst.domain}" 2>/dev/null || true
docker exec -u www-data nextcloud${i + 1}-app php occ config:system:set overwriteprotocol --value="https" 2>/dev/null || true`
    )
    .join("\n\n");

  // Generate credentials content
  const credentialsContent = instances
    .map(
      (inst, i) => `\${DOMAIN${i + 1}}
--------------------------
URL: https://\${DOMAIN${i + 1}}
Admin User: ${inst.adminUser}
Admin Password: \${NC${i + 1}_ADMIN_PASSWORD}`
    )
    .join("\n\n");

  // Generate database passwords for credentials
  const dbPasswordsCredentials = instances.map((_, i) => `DB${i + 1}: \${DB${i + 1}_PASSWORD}`).join("\n");

  // Generate service status check
  const serviceStatusCheck = [
    "caddy",
    ...instances.flatMap((_, i) => [
      `nginx${i + 1}`,
      `nextcloud${i + 1}-app`,
      `nextcloud${i + 1}-db`,
      `nextcloud${i + 1}-redis`,
    ]),
  ].join(" ");

  // Generate manage.sh occ commands
  const occCommands = instances
    .map(
      (_, i) => `    occ${i + 1})
        docker exec -u www-data nextcloud${i + 1}-app php occ \${@:2}
        ;;`
    )
    .join("\n");

  // Generate manage.sh permission fixes
  const managePermissionFixes = instances
    .map((_, i) => `        docker exec nextcloud${i + 1}-app chown -R www-data:www-data /var/www/html`)
    .join("\n");

  // Generate manage.sh usage
  const manageUsage = instances.map((_, i) => `occ${i + 1}`).join("|");

  // Generate URLs for final output
  const finalUrls = instances
    .map((_, i) => `echo -e "  \\xf0\\x9f\\x94\\x92 \${GREEN}https://\${DOMAIN${i + 1}}\${NC}"`)
    .join("\n");

  return `#!/bin/bash

# ============================================================================
# Nextcloud Multi-tenant Deployment with Caddy
# Generated by Nextcloud Docker Generator
# ============================================================================

set -e

# Color codes
RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
BLUE='\\033[0;34m'
CYAN='\\033[0;36m'
NC='\\033[0m'

# Configuration
${domainVars}
PROJECT_DIR="${projectDir}"

print_info() { echo -e "\${BLUE}[INFO]\${NC} $1"; }
print_success() { echo -e "\${GREEN}[\\u2713]\${NC} $1"; }
print_warning() { echo -e "\${YELLOW}[!]\${NC} $1"; }
print_error() { echo -e "\${RED}[\\u2717]\${NC} $1"; }

# Banner
clear
echo -e "\${CYAN}============================================================================\${NC}"
echo -e "\${CYAN}     NEXTCLOUD WITH CADDY - DEPLOYMENT\${NC}"
echo -e "\${CYAN}============================================================================\${NC}"
echo ""
echo "This script will deploy:"
${bannerDomains}
echo ""
echo "Features:"
echo "  \\u2713 Automatic HTTPS with Caddy"
echo "  \\u2713 Fixed nginx configuration for dashboard"
echo "  \\u2713 Proper PHP-FPM handling"
echo "  \\u2713 Production optimized"
echo ""
echo -e "\${CYAN}============================================================================\${NC}"
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

# Check DNS
print_info "Checking DNS configuration..."
PUBLIC_IP=$(curl -s ifconfig.me)
print_info "Server IP: \${PUBLIC_IP}"

for domain in ${domainList}; do
    DOMAIN_IP=$(dig +short $domain | tail -n1)
    if [ "$DOMAIN_IP" = "$PUBLIC_IP" ]; then
        print_success "$domain \\u2192 $DOMAIN_IP \\u2713"
    else
        print_warning "$domain \\u2192 $DOMAIN_IP (should be $PUBLIC_IP)"
    fi
done

# Set email
ACME_EMAIL="${acmeEmail}"

# Create directory structure
print_info "Creating directory structure..."
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR
mkdir -p caddy/{data,config}
mkdir -p nginx
mkdir -p backups

# Generate secure passwords
print_info "Generating secure passwords..."
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-24
}

${passwordGeneration}

# Create .env file
print_info "Creating environment configuration..."
cat > .env << EOF
# Generated: $(date)
${envContent}
ACME_EMAIL=\${ACME_EMAIL}
EOF
chmod 600 .env

# Create Caddyfile
print_info "Creating Caddyfile..."
cat > caddy/Caddyfile << EOF
{
    email \${ACME_EMAIL}
}

${caddyfileEntries}
EOF

# Create FIXED nginx configuration for FPM
print_info "Creating fixed nginx configurations..."

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

        client_max_body_size 10G;
        client_body_timeout 300s;
        fastcgi_buffers 64 4K;

        gzip on;
        gzip_vary on;
        gzip_comp_level 4;
        gzip_min_length 256;

        client_body_buffer_size 512k;

        add_header Referrer-Policy                   "no-referrer"       always;
        add_header X-Content-Type-Options            "nosniff"           always;
        add_header X-Frame-Options                   "SAMEORIGIN"        always;
        add_header X-Permitted-Cross-Domain-Policies "none"              always;
        add_header X-Robots-Tag                      "noindex, nofollow" always;
        add_header X-XSS-Protection                  "1; mode=block"     always;

        root /var/www/html;

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
        location ~ ^/(?:\\.|autotest|occ|issue|indie|db_|console)                { return 404; }

        location ~ \\.php(?:$|/) {
            rewrite ^/(?!index|remote|public|cron|core\\/ajax\\/update|status|ocs\\/v[12]|updater\\/.+|oc[sm]-provider\\/.+|.+\\/richdocumentscode\\/proxy) /index.php$request_uri;

            fastcgi_split_path_info ^(.+?\\.php)(/.*)$;
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

        location ~ \\.(?:css|js|mjs|svg|gif|png|jpg|ico|wasm|tflite|map|ogg|flac)$ {
            try_files $uri /index.php$request_uri;
            add_header Cache-Control "public, max-age=15778463";
            access_log off;

            location ~ \\.woff2?$ {
                try_files $uri /index.php$request_uri;
                expires 7d;
                access_log off;
            }

            location /remote {
                return 301 /remote.php$request_uri;
            }
        }

        location / {
            try_files $uri $uri/ /index.php$request_uri;
        }
    }
}
NGINX_TEMPLATE

${nginxConfigCreation}

rm nginx/nextcloud.conf.template

print_success "Nginx configurations created"

# Create docker-compose.yml
print_info "Creating docker-compose.yml..."
cat > docker-compose.yml << 'COMPOSE'
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
      - ${caddyDependsOn}

${generateNextcloudServices()}

volumes:
${volumes}

networks:
  proxy-tier:
${networks}
COMPOSE

print_success "docker-compose.yml created"

# Create networks
print_info "Creating Docker networks..."
docker network create proxy-tier 2>/dev/null || true
${networkCreation}

# Deploy
print_info "Starting deployment..."
docker compose up -d

# Wait for services
print_info "Waiting for services to initialize (30 seconds)..."
sleep 30

# Fix any permission issues
print_info "Fixing permissions..."
${permissionFixes}

# Run initial setup commands
print_info "Running initial setup..."
${initialSetup}

# Configure trusted domains and proxies
print_info "Configuring Nextcloud settings..."
${nextcloudConfig}

# Save credentials
print_info "Saving credentials..."
cat > credentials.txt << CREDS
============================================================================
                 NEXTCLOUD WITH CADDY - CREDENTIALS
============================================================================
Generated: $(date)

${credentialsContent}

Database Passwords (for backups):
${dbPasswordsCredentials}

============================================================================
IMPORTANT: Save these credentials and delete this file!
============================================================================
CREDS
chmod 600 credentials.txt

# Check status
echo ""
print_info "Checking service status..."
SERVICES_OK=true
for service in ${serviceStatusCheck}; do
    if docker ps | grep -q $service; then
        print_success "$service running"
    else
        print_error "$service not running"
        SERVICES_OK=false
    fi
done

# Create management script
print_info "Creating management script..."
cat > manage.sh << 'MANAGE'
#!/bin/bash
case "$1" in
    logs)
        docker compose logs -f \${2}
        ;;
    restart)
        docker compose restart \${2}
        ;;
    status)
        docker compose ps
        ;;
    fix-permissions)
${managePermissionFixes}
        ;;
${occCommands}
    *)
        echo "Usage: $0 {logs|restart|status|fix-permissions|${manageUsage}} [args]"
        ;;
esac
MANAGE
chmod +x manage.sh

# Final output
echo ""
echo -e "\${GREEN}============================================================================\${NC}"
if [ "$SERVICES_OK" = true ]; then
    echo -e "\${GREEN}           DEPLOYMENT COMPLETE!\${NC}"
else
    echo -e "\${YELLOW}           DEPLOYMENT COMPLETE WITH WARNINGS\${NC}"
fi
echo -e "\${GREEN}============================================================================\${NC}"
echo ""
echo "Caddy will automatically obtain SSL certificates on first access!"
echo ""
echo "Access your Nextcloud instances:"
${finalUrls}
echo ""
echo -e "\${YELLOW}Credentials saved to: credentials.txt\${NC}"
echo -e "\${RED}Delete credentials.txt after saving passwords!\${NC}"
echo ""
echo "Management commands:"
echo "  ./manage.sh status              - Check status"
echo "  ./manage.sh logs [service]      - View logs"
echo "  ./manage.sh restart [service]   - Restart service"
echo "  ./manage.sh fix-permissions     - Fix file permissions"
${instances.map((_, i) => `echo "  ./manage.sh occ${i + 1} [command]      - Run occ on instance ${i + 1}"`).join("\n")}
echo ""
echo "If you get 403 errors, run:"
echo "  ./manage.sh fix-permissions"
echo "  ./manage.sh restart"
echo ""
echo -e "\${GREEN}============================================================================\${NC}"
`;
}
