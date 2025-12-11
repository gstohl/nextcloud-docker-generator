#!/bin/bash

# ============================================================================
# Nextcloud Cleanup Script
# Removes all containers, volumes, networks, and generated files
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
echo -e "${CYAN}============================================================================${NC}"
echo -e "${CYAN}     NEXTCLOUD CLEANUP SCRIPT${NC}"
echo -e "${CYAN}============================================================================${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    print_error "docker-compose.yml not found!"
    echo "Please run this script from your Nextcloud project directory"
    echo "(the directory containing docker-compose.yml)"
    exit 1
fi

# Detect number of instances from docker-compose.yml
NUM_INSTANCES=$(grep -c "nextcloud[0-9]*-app" docker-compose.yml 2>/dev/null || echo "0")
if [ "$NUM_INSTANCES" -eq 0 ]; then
    # Fallback: count by looking for db services
    NUM_INSTANCES=$(grep -c "POSTGRES_DB: nextcloud" docker-compose.yml 2>/dev/null || echo "1")
fi
print_info "Detected $NUM_INSTANCES Nextcloud instance(s)"

# Confirmation
echo ""
echo -e "${RED}WARNING: This will permanently delete:${NC}"
echo "  - All Nextcloud containers"
echo "  - All database data"
echo "  - All Redis data"
echo "  - All uploaded files"
echo "  - All configuration files"
echo "  - Docker networks"
echo ""
echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
echo ""
read -p "Type 'DELETE' to confirm: " confirm

if [ "$confirm" != "DELETE" ]; then
    print_info "Cleanup cancelled"
    exit 0
fi

echo ""

# Stop and remove containers
print_info "Stopping and removing containers..."
docker compose down --remove-orphans 2>/dev/null || true

# Remove volumes
print_info "Removing Docker volumes..."
for i in $(seq 1 $NUM_INSTANCES); do
    # Get project name (directory name) for volume prefix
    PROJECT_NAME=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')

    # Try with project prefix first, then without
    for vol in "nc${i}_html" "db${i}_data" "redis${i}_data"; do
        docker volume rm "${PROJECT_NAME}_${vol}" 2>/dev/null && print_success "Removed volume ${PROJECT_NAME}_${vol}" || true
        docker volume rm "${vol}" 2>/dev/null && print_success "Removed volume ${vol}" || true
    done
done

# Also try to remove any remaining volumes from compose
docker compose down -v 2>/dev/null || true

# Remove networks
print_info "Removing Docker networks..."
docker network rm proxy-tier 2>/dev/null && print_success "Removed network proxy-tier" || true
for i in $(seq 1 $NUM_INSTANCES); do
    docker network rm "backend${i}" 2>/dev/null && print_success "Removed network backend${i}" || true
done

# Remove generated files
print_info "Removing generated files..."

# Remove nginx configs
if [ -d "nginx" ]; then
    rm -rf nginx
    print_success "Removed nginx/"
fi

# Remove caddy configs
if [ -d "caddy" ]; then
    rm -rf caddy
    print_success "Removed caddy/"
fi

# Remove backups directory (ask first)
if [ -d "backups" ]; then
    read -p "Remove backups directory? [y/N]: " remove_backups
    if [[ "$remove_backups" =~ ^[Yy] ]]; then
        rm -rf backups
        print_success "Removed backups/"
    else
        print_info "Kept backups/"
    fi
fi

# Remove config files
[ -f "docker-compose.yml" ] && rm -f docker-compose.yml && print_success "Removed docker-compose.yml"
[ -f ".env" ] && rm -f .env && print_success "Removed .env"
[ -f "credentials.txt" ] && rm -f credentials.txt && print_success "Removed credentials.txt"
[ -f "manage.sh" ] && rm -f manage.sh && print_success "Removed manage.sh"

# Final cleanup - prune unused volumes (optional)
echo ""
read -p "Run 'docker volume prune' to remove any orphaned volumes? [y/N]: " prune_volumes
if [[ "$prune_volumes" =~ ^[Yy] ]]; then
    docker volume prune -f
    print_success "Pruned orphaned volumes"
fi

echo ""
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}                    CLEANUP COMPLETE${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo ""
echo "All Nextcloud resources have been removed."
echo "You can now re-run deploy-nextcloud.sh for a fresh installation."
echo ""
