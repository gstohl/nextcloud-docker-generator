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

# Ask for project directory
read -p "Project directory name [nextcloud-caddy]: " PROJECT_DIR
PROJECT_DIR=${PROJECT_DIR:-nextcloud-caddy}

# Check if project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
    print_error "Directory '$PROJECT_DIR' not found!"
    echo "Available directories:"
    ls -d */ 2>/dev/null || echo "  (none)"
    exit 1
fi

# Check if it contains docker-compose.yml
if [ ! -f "$PROJECT_DIR/docker-compose.yml" ]; then
    print_error "docker-compose.yml not found in '$PROJECT_DIR'!"
    echo "This doesn't appear to be a Nextcloud deployment directory."
    exit 1
fi

# Detect number of instances from docker-compose.yml
NUM_INSTANCES=$(grep -c "nextcloud[0-9]*-app" "$PROJECT_DIR/docker-compose.yml" 2>/dev/null || echo "0")
if [ "$NUM_INSTANCES" -eq 0 ]; then
    # Fallback: count by looking for db services
    NUM_INSTANCES=$(grep -c "POSTGRES_DB: nextcloud" "$PROJECT_DIR/docker-compose.yml" 2>/dev/null || echo "1")
fi
print_info "Detected $NUM_INSTANCES Nextcloud instance(s) in '$PROJECT_DIR'"

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
cd "$PROJECT_DIR"
docker compose down --remove-orphans 2>/dev/null || true

# Remove volumes
print_info "Removing Docker volumes..."
# Get project name (directory name) for volume prefix - docker compose uses this
PROJECT_NAME=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')

for i in $(seq 1 $NUM_INSTANCES); do
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

# Go back to parent directory
cd ..

# Remove generated files
print_info "Removing generated files in '$PROJECT_DIR'..."

# Ask if user wants to remove the entire directory or just contents
echo ""
echo "How do you want to clean up?"
echo "  1) Remove entire '$PROJECT_DIR' directory"
echo "  2) Remove only generated files (keep directory)"
read -p "Choice [1]: " cleanup_choice
cleanup_choice=${cleanup_choice:-1}

if [ "$cleanup_choice" = "1" ]; then
    rm -rf "$PROJECT_DIR"
    print_success "Removed entire '$PROJECT_DIR' directory"
else
    # Remove nginx configs
    if [ -d "$PROJECT_DIR/nginx" ]; then
        rm -rf "$PROJECT_DIR/nginx"
        print_success "Removed nginx/"
    fi

    # Remove caddy configs
    if [ -d "$PROJECT_DIR/caddy" ]; then
        rm -rf "$PROJECT_DIR/caddy"
        print_success "Removed caddy/"
    fi

    # Remove backups directory (ask first)
    if [ -d "$PROJECT_DIR/backups" ]; then
        read -p "Remove backups directory? [y/N]: " remove_backups
        if [[ "$remove_backups" =~ ^[Yy] ]]; then
            rm -rf "$PROJECT_DIR/backups"
            print_success "Removed backups/"
        else
            print_info "Kept backups/"
        fi
    fi

    # Remove config files
    [ -f "$PROJECT_DIR/docker-compose.yml" ] && rm -f "$PROJECT_DIR/docker-compose.yml" && print_success "Removed docker-compose.yml"
    [ -f "$PROJECT_DIR/.env" ] && rm -f "$PROJECT_DIR/.env" && print_success "Removed .env"
    [ -f "$PROJECT_DIR/credentials.txt" ] && rm -f "$PROJECT_DIR/credentials.txt" && print_success "Removed credentials.txt"
    [ -f "$PROJECT_DIR/manage.sh" ] && rm -f "$PROJECT_DIR/manage.sh" && print_success "Removed manage.sh"
fi

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
