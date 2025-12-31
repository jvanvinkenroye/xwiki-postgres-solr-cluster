#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# XWiki Cluster Setup Script
# Automated setup for XWiki high-availability cluster
# ---------------------------------------------------------------------------

set -euo pipefail

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Directories
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PARENT_DIR="$(dirname "${SCRIPT_DIR}")"
readonly SOLR_INIT_DIR="${PARENT_DIR}/solr-init"

# Functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker is not installed"
        exit 1
    fi

    if ! docker compose version >/dev/null 2>&1; then
        print_error "Docker Compose is not installed"
        exit 1
    fi

    print_success "Docker and Docker Compose found"
}

# Download Solr configuration archive (JAR or ZIP depending on version)
download_solr_jar() {
    local version="$1"

    # Determine artifact name and extension based on XWiki version
    # Versions >= 16.0.0 use xwiki-platform-search-solr-server-core-minimal (ZIP format)
    # Versions < 16.0.0 use xwiki-platform-search-solr-server-data (JAR format)
    # Both JAR and ZIP work with solr-init.sh since they're both handled by unzip
    local major_version
    major_version=$(echo "$version" | cut -d. -f1)

    local artifact_name
    local file_ext
    local artifact_base

    if [ "$major_version" -ge 16 ]; then
        artifact_base="xwiki-platform-search-solr-server-core-minimal"
        file_ext="zip"
    else
        artifact_base="xwiki-platform-search-solr-server-data"
        file_ext="jar"
    fi

    local file_name="${artifact_base}-${version}.${file_ext}"
    local file_path="${SOLR_INIT_DIR}/${file_name}"
    local file_url="https://maven.xwiki.org/releases/org/xwiki/platform/${artifact_base}/${version}/${file_name}"

    # Create solr-init directory if needed
    mkdir -p "${SOLR_INIT_DIR}"

    # Check if file already exists (check for both JAR and ZIP)
    if [ -f "${file_path}" ]; then
        print_success "Solr configuration already exists: ${file_name}"
        return 0
    fi

    # Also check for alternate format in case user has old file
    local alt_ext
    if [ "$file_ext" = "jar" ]; then
        alt_ext="zip"
    else
        alt_ext="jar"
    fi
    local alt_file="${artifact_base}-${version}.${alt_ext}"
    if [ -f "${SOLR_INIT_DIR}/${alt_file}" ]; then
        print_success "Solr configuration already exists: ${alt_file}"
        return 0
    fi

    print_info "Downloading Solr configuration (${file_ext} format)..."
    print_info "Artifact: ${artifact_base}"
    print_info "Version: ${version}"
    print_info "URL: ${file_url}"

    # Download using wget or curl
    if command -v wget >/dev/null 2>&1; then
        wget -O "${file_path}" "${file_url}" 2>&1 | grep -E "(saved|failed)" || true
    elif command -v curl >/dev/null 2>&1; then
        curl -fSL -o "${file_path}" "${file_url}"
    else
        print_error "Neither wget nor curl is available"
        return 1
    fi

    # Verify download
    if [ -f "${file_path}" ] && [ -s "${file_path}" ]; then
        local size
        size=$(du -h "${file_path}" | cut -f1)
        print_success "Downloaded Solr configuration (${size}): ${file_name}"
        return 0
    else
        print_error "Download failed or file is empty"
        print_error "Please verify the version exists at:"
        print_error "  https://maven.xwiki.org/releases/org/xwiki/platform/${artifact_base}/"
        return 1
    fi
}

# Check and setup Solr initialization
setup_solr() {
    print_header "Setting up Solr Configuration"

    # Check if solr-init.sh exists
    if [ ! -f "${SOLR_INIT_DIR}/solr-init.sh" ]; then
        print_info "Copying solr-init.sh script..."

        # Check if it exists in contrib
        if [ -f "${PARENT_DIR}/../contrib/solr/solr-init.sh" ]; then
            cp "${PARENT_DIR}/../contrib/solr/solr-init.sh" "${SOLR_INIT_DIR}/"
            chmod +x "${SOLR_INIT_DIR}/solr-init.sh"
        else
            print_warning "solr-init.sh not found in contrib directory"
            print_info "Please ensure the script is in ${SOLR_INIT_DIR}/"
        fi
    fi

    # Check if Solr configuration exists (JAR or ZIP)
    local config_count
    config_count=$(find "${SOLR_INIT_DIR}" -name "*.jar" -o -name "*.zip" 2>/dev/null | wc -l)

    if [ "$config_count" -eq 0 ]; then
        print_info "Solr configuration archive not found, will download..."
        return 1
    else
        print_success "Solr configuration already set up"
        return 0
    fi
}

# Get XWiki version from user
get_xwiki_version() {
    print_header "XWiki Version Selection"

    echo ""
    echo "Which XWiki version do you want to use?"
    echo ""
    echo "  1) 17.10.2 (Latest stable - Recommended)"
    echo "  2) 16.10.15 (LTS)"
    echo "  3) 17.4.7 (Older stable)"
    echo "  4) Custom version"
    echo ""
    read -p "Select option [1-4] (default: 1): " -r choice

    local version=""
    case "${choice:-1}" in
        1)
            version="17.10.2"
            ;;
        2)
            version="16.10.15"
            ;;
        3)
            version="17.4.7"
            ;;
        4)
            read -p "Enter custom XWiki version: " -r version
            ;;
        *)
            version="17.10.2"
            ;;
    esac

    echo "$version"
}

# Create environment file
create_env() {
    print_header "Creating Environment File"

    local env_file="${SCRIPT_DIR}/.env"

    if [ -f "${env_file}" ]; then
        print_warning ".env file already exists"
        read -p "Overwrite? [y/N]: " -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Using existing .env file"
            return 0
        fi
    fi

    cp "${SCRIPT_DIR}/.env.example" "${env_file}"

    # Generate random passwords
    if command -v openssl >/dev/null 2>&1; then
        local db_root_pass
        local db_user_pass
        db_root_pass=$(openssl rand -base64 16)
        db_user_pass=$(openssl rand -base64 16)

        # Use | as delimiter to avoid issues with / in base64 passwords
        # macOS sed requires '' after -i, while GNU sed works with or without
        sed -i.bak "s|changeme_root_password|${db_root_pass}|g" "${env_file}"
        sed -i.bak "s|changeme_xwiki_password|${db_user_pass}|g" "${env_file}"
        rm -f "${env_file}.bak"
        print_success "Created .env with random passwords"
    else
        print_warning "Created .env - please set passwords manually"
    fi
}

# Select number of nodes
select_nodes() {
    print_header "Cluster Size Configuration"

    echo ""
    echo "How many XWiki nodes do you want to run?"
    echo ""
    echo "  2 nodes - Minimum for high availability"
    echo "  3 nodes - Recommended for production (default)"
    echo ""
    read -p "Number of nodes [2-3] (default: 3): " -r node_count

    case "${node_count:-3}" in
        2)
            print_info "Configuring 2-node cluster"
            # Comment out web3 in docker-compose
            if command -v sed >/dev/null 2>&1; then
                sed -i.bak '/web3:/,/start_period: 120s/s/^/# /' \
                    "${SCRIPT_DIR}/docker-compose-cluster.yml" 2>/dev/null || true
                rm -f "${SCRIPT_DIR}/docker-compose-cluster.yml.bak"
            fi
            ;;
        3)
            print_info "Configuring 3-node cluster (recommended)"
            ;;
        *)
            print_warning "Invalid selection, using 3 nodes"
            ;;
    esac
}

# Start cluster
start_cluster() {
    print_header "Starting Cluster"

    print_info "This may take 3-5 minutes..."
    echo ""

    cd "${SCRIPT_DIR}"
    docker compose -f docker-compose-cluster.yml up -d

    print_success "Cluster started"
}

# Wait for services
wait_for_services() {
    print_header "Waiting for Services"

    local max_wait=300
    local elapsed=0

    while [ $elapsed -lt $max_wait ]; do
        local healthy=0
        local total=5  # db, solr, web1, web2, loadbalancer

        # Check each service
        docker inspect --format='{{.State.Health.Status}}' xwiki-cluster-db 2>/dev/null | grep -q "healthy" && ((healthy++)) || true
        docker inspect --format='{{.State.Health.Status}}' xwiki-cluster-solr 2>/dev/null | grep -q "healthy" && ((healthy++)) || true
        docker inspect --format='{{.State.Health.Status}}' xwiki-cluster-node1 2>/dev/null | grep -q "healthy" && ((healthy++)) || true
        docker inspect --format='{{.State.Health.Status}}' xwiki-cluster-node2 2>/dev/null | grep -q "healthy" && ((healthy++)) || true
        docker inspect --format='{{.State.Health.Status}}' xwiki-cluster-lb 2>/dev/null | grep -q "healthy" && ((healthy++)) || true

        echo -ne "\r  Progress: [${healthy}/${total}] services healthy (${elapsed}s elapsed)"

        if [ $healthy -ge 4 ]; then  # Allow node3 to be optional
            echo ""
            print_success "Core services are healthy!"
            return 0
        fi

        sleep 5
        ((elapsed += 5))
    done

    echo ""
    print_warning "Some services may still be starting. Check logs:"
    echo "  docker compose -f docker-compose-cluster.yml logs -f"
}

# Print completion
print_completion() {
    print_header "Cluster Setup Complete!"

    echo ""
    echo -e "${GREEN}XWiki Cluster is now running!${NC}"
    echo ""
    echo -e "${BLUE}Access Points:${NC}"
    echo "  → XWiki (via Load Balancer): http://localhost:8080"
    echo "  → Nginx Status Page:         http://localhost:8081/nginx_status"
    echo "  → Nginx Health Check:        http://localhost:8081/health"
    echo "  → Solr Admin UI:             http://localhost:8983/solr"
    echo ""
    echo -e "${YELLOW}Cluster Status:${NC}"
    docker compose -f "${SCRIPT_DIR}/docker-compose-cluster.yml" ps
    echo ""
    echo -e "${YELLOW}Useful Commands:${NC}"
    echo "  View logs:       docker compose -f docker-compose-cluster.yml logs -f"
    echo "  Check health:    docker compose -f docker-compose-cluster.yml ps"
    echo "  Stop cluster:    docker compose -f docker-compose-cluster.yml stop"
    echo "  Start cluster:   docker compose -f docker-compose-cluster.yml start"
    echo "  Remove cluster:  docker compose -f docker-compose-cluster.yml down"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Open http://localhost:8080 in your browser"
    echo "  2. Complete the XWiki Distribution Wizard"
    echo "  3. Monitor cluster formation in logs"
    echo "  4. Check Nginx status at http://localhost:8081/nginx_status"
    echo "  5. Verify all nodes are healthy with 'docker compose ps'"
    echo ""
    echo -e "${BLUE}Documentation:${NC}"
    echo "  → See clustering/README.md for detailed information"
    echo ""
}

# Set Solr permissions
set_solr_permissions() {
    print_header "Setting Solr Permissions"

    # Detect OS type
    local os_type
    os_type=$(uname -s)

    if [[ "$os_type" == "Darwin" ]]; then
        # macOS: Docker Desktop handles UID mapping automatically
        # We just need to ensure files are readable
        print_info "Detected macOS - ensuring files are readable..."

        chmod -R u+r "${SOLR_INIT_DIR}" 2>/dev/null || true
        chmod u+x "${SOLR_INIT_DIR}" 2>/dev/null || true
        chmod u+x "${SOLR_INIT_DIR}/solr-init.sh" 2>/dev/null || true

        print_success "File permissions set for macOS Docker Desktop"
        print_info "Note: On macOS, Docker Desktop automatically handles UID/GID mapping"
        return 0
    fi

    # Linux: Need proper UID/GID ownership
    print_info "Detected Linux - Solr requires ownership by UID:GID 8983:8983"

    # Check current ownership
    local current_owner
    current_owner=$(stat -c '%u:%g' "${SOLR_INIT_DIR}" 2>/dev/null || echo "unknown")

    if [ "$current_owner" = "8983:8983" ]; then
        print_success "Permissions already correct (8983:8983)"
        return 0
    fi

    print_info "Current ownership: ${current_owner}, need: 8983:8983"

    # Try different methods to set ownership (Linux only)

    # Method 1: Direct sudo (passwordless)
    if command -v sudo >/dev/null 2>&1; then
        if sudo -n chown -R 8983:8983 "${SOLR_INIT_DIR}" 2>/dev/null; then
            print_success "Permissions set using sudo"
            return 0
        fi
    fi

    # Method 2: Running as root
    if [ "$EUID" -eq 0 ]; then
        chown -R 8983:8983 "${SOLR_INIT_DIR}"
        print_success "Permissions set (running as root)"
        return 0
    fi

    # Method 3: Docker with volume mount
    if docker run --rm -v "${SOLR_INIT_DIR}:/data" alpine chown -R 8983:8983 /data 2>/dev/null; then
        print_success "Permissions set using Docker"
        return 0
    fi

    # All automatic methods failed
    print_warning "Cannot set permissions automatically on Linux"
    print_warning ""
    print_warning "Please run ONE of these commands in another terminal:"
    echo ""
    echo "  Option 1 (recommended):"
    echo "  sudo chown -R 8983:8983 ${SOLR_INIT_DIR}"
    echo ""
    echo "  Option 2 (using Docker):"
    echo "  docker run --rm -v ${SOLR_INIT_DIR}:/data alpine chown -R 8983:8983 /data"
    echo ""

    read -p "Press ENTER after setting permissions, or Ctrl+C to abort..." -r

    # Verify permissions
    current_owner=$(stat -c '%u:%g' "${SOLR_INIT_DIR}" 2>/dev/null || echo "unknown")
    if [ "$current_owner" = "8983:8983" ]; then
        print_success "Permissions verified (8983:8983)"
        return 0
    else
        print_warning "Permissions still not set correctly: ${current_owner}"
        print_warning "Solr container may have issues, but continuing..."
        return 1
    fi
}

# Main
main() {
    clear

    print_header "XWiki High Availability Cluster Setup"

    echo "This script will set up a production-ready XWiki cluster with:"
    echo "  • Multiple XWiki nodes (2-3)"
    echo "  • Nginx load balancer with sticky sessions"
    echo "  • PostgreSQL database (shared)"
    echo "  • Solr search engine (shared)"
    echo "  • JGroups cluster communication"
    echo ""

    read -p "Continue? [Y/n]: " -r response
    if [[ "$response" =~ ^[Nn]$ ]]; then
        echo "Setup cancelled."
        exit 0
    fi

    # Run setup steps
    check_prerequisites

    # Get XWiki version
    local xwiki_version
    xwiki_version=$(get_xwiki_version)
    print_info "Selected XWiki version: ${xwiki_version}"

    # Setup Solr
    if ! setup_solr; then
        print_info "Downloading Solr configuration for version ${xwiki_version}..."
        download_solr_jar "${xwiki_version}" || {
            print_error "Failed to download Solr JAR"
            exit 1
        }
    fi

    # Set Solr permissions
    set_solr_permissions || {
        print_warning "Continuing despite permission issues..."
        print_warning "You may need to manually run:"
        echo "  sudo chown -R 8983:8983 ${SOLR_INIT_DIR}"
    }

    create_env
    select_nodes
    start_cluster
    wait_for_services
    print_completion
}

main "$@"
