#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# XWiki PostgreSQL + Solr Setup Script
# Automated setup for XWiki with PostgreSQL database and external Solr
# ---------------------------------------------------------------------------

set -euo pipefail

# Color output for better readability
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
readonly SOLR_INIT_DIR="${SCRIPT_DIR}/solr-init"
readonly DEFAULT_XWIKI_VERSION="17.10.2"

# Function to print colored messages
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

# Function to print section header
print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo ""
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    local all_ok=true

    # Check Docker
    if command_exists docker; then
        local docker_version
        docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        print_success "Docker found: version ${docker_version}"
    else
        print_error "Docker is not installed"
        all_ok=false
    fi

    # Check Docker Compose
    if docker compose version >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker compose version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        print_success "Docker Compose found: version ${compose_version}"
    else
        print_error "Docker Compose is not installed or not available"
        all_ok=false
    fi

    # Check wget or curl
    if command_exists wget; then
        print_success "wget found"
    elif command_exists curl; then
        print_success "curl found"
    else
        print_error "Neither wget nor curl is installed (needed to download Solr JAR)"
        all_ok=false
    fi

    if [ "$all_ok" = false ]; then
        print_error "Please install missing prerequisites before continuing"
        exit 1
    fi

    print_success "All prerequisites satisfied"
}

# Function to get XWiki version from user
get_xwiki_version() {
    local version=""

    echo ""
    print_info "Which XWiki version do you want to use?"
    echo ""
    echo "  1) 17.10.2 (Latest stable - Recommended)"
    echo "  2) 16.10.15 (LTS)"
    echo "  3) 17.4.7 (Older stable)"
    echo "  4) Custom version"
    echo ""
    read -p "Select option [1-4] (default: 1): " -r choice

    case "${choice:-1}" in
        1)
            version="${DEFAULT_XWIKI_VERSION}"
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
            version="${DEFAULT_XWIKI_VERSION}"
            ;;
    esac

    echo "$version"
}

# Function to download Solr configuration JAR
download_solr_jar() {
    local version="$1"
    local jar_name="xwiki-platform-search-solr-server-data-${version}.jar"
    local jar_path="${SOLR_INIT_DIR}/${jar_name}"
    local jar_url="https://maven.xwiki.org/releases/org/xwiki/platform/xwiki-platform-search-solr-server-data/${version}/${jar_name}"

    print_header "Downloading Solr Configuration"

    # Create solr-init directory if it doesn't exist
    mkdir -p "${SOLR_INIT_DIR}"

    # Check if JAR already exists
    if [ -f "${jar_path}" ]; then
        print_warning "JAR file already exists: ${jar_name}"
        read -p "Do you want to re-download? [y/N]: " -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Using existing JAR file"
            return 0
        fi
        rm -f "${jar_path}"
    fi

    print_info "Downloading from: ${jar_url}"

    # Download using wget or curl
    if command_exists wget; then
        wget -O "${jar_path}" "${jar_url}" || {
            print_error "Failed to download JAR file"
            return 1
        }
    else
        curl -fSL -o "${jar_path}" "${jar_url}" || {
            print_error "Failed to download JAR file"
            return 1
        }
    fi

    # Verify download
    if [ -f "${jar_path}" ] && [ -s "${jar_path}" ]; then
        local size
        size=$(du -h "${jar_path}" | cut -f1)
        print_success "Downloaded JAR file (${size}): ${jar_name}"
    else
        print_error "Downloaded file is empty or missing"
        return 1
    fi

    return 0
}

# Function to set Solr permissions
set_solr_permissions() {
    print_header "Setting File Permissions"

    print_info "Solr requires ownership by UID:GID 8983:8983"

    # Check if running as root or with sudo
    if [ "$EUID" -eq 0 ]; then
        chown -R 8983:8983 "${SOLR_INIT_DIR}"
        print_success "Permissions set successfully"
    elif command_exists sudo; then
        print_warning "Sudo access required to set permissions"
        sudo chown -R 8983:8983 "${SOLR_INIT_DIR}" || {
            print_error "Failed to set permissions"
            print_warning "You may need to run manually: sudo chown -R 8983:8983 ${SOLR_INIT_DIR}"
            return 1
        }
        print_success "Permissions set successfully"
    else
        print_warning "Cannot set permissions automatically"
        print_warning "Please run manually: sudo chown -R 8983:8983 ${SOLR_INIT_DIR}"
        return 1
    fi

    # Verify permissions
    local owner
    owner=$(ls -ld "${SOLR_INIT_DIR}" | awk '{print $3":"$4}')
    if [ "$owner" = "8983:8983" ] || [ "$owner" = "8983:8983" ]; then
        print_success "Permissions verified: ${owner}"
    else
        print_warning "Unexpected ownership: ${owner} (expected 8983:8983)"
    fi
}

# Function to create .env file
create_env_file() {
    print_header "Creating Environment Configuration"

    local env_file="${SCRIPT_DIR}/.env"

    if [ -f "${env_file}" ]; then
        print_warning ".env file already exists"
        read -p "Do you want to overwrite it? [y/N]: " -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Keeping existing .env file"
            return 0
        fi
    fi

    if [ ! -f "${SCRIPT_DIR}/.env.example" ]; then
        print_error ".env.example file not found"
        return 1
    fi

    cp "${SCRIPT_DIR}/.env.example" "${env_file}"

    # Generate random passwords
    local db_root_pass
    local db_user_pass
    db_root_pass=$(openssl rand -base64 16 2>/dev/null || echo "change_me_$(date +%s)")
    db_user_pass=$(openssl rand -base64 16 2>/dev/null || echo "change_me_$(date +%s)")

    # Update passwords in .env file
    if command_exists sed; then
        sed -i.bak "s/changeme_root_password/${db_root_pass}/g" "${env_file}"
        sed -i.bak "s/changeme_xwiki_password/${db_user_pass}/g" "${env_file}"
        rm -f "${env_file}.bak"
    fi

    print_success "Created .env file with generated passwords"
    print_warning "Please review ${env_file} and adjust settings as needed"
}

# Function to start services
start_services() {
    print_header "Starting Docker Services"

    local compose_file="${SCRIPT_DIR}/docker-compose-postgres-solr.yml"

    if [ ! -f "${compose_file}" ]; then
        print_error "docker-compose file not found: ${compose_file}"
        return 1
    fi

    print_info "Starting services (this may take a few minutes)..."

    docker compose -f "${compose_file}" up -d || {
        print_error "Failed to start services"
        return 1
    }

    print_success "Services started successfully"
    echo ""
    print_info "Waiting for services to be healthy..."
    echo ""

    # Wait for services to be healthy
    local max_wait=180
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        local healthy=0
        local total=3

        # Check each service
        if docker inspect --format='{{.State.Health.Status}}' xwiki-postgres-db 2>/dev/null | grep -q "healthy"; then
            ((healthy++))
        fi

        if docker inspect --format='{{.State.Health.Status}}' xwiki-solr 2>/dev/null | grep -q "healthy"; then
            ((healthy++))
        fi

        if docker inspect --format='{{.State.Health.Status}}' xwiki-web 2>/dev/null | grep -q "healthy"; then
            ((healthy++))
        fi

        echo -ne "\r  Progress: [${healthy}/${total}] services healthy (${elapsed}s elapsed)"

        if [ $healthy -eq $total ]; then
            echo ""
            print_success "All services are healthy!"
            return 0
        fi

        sleep 5
        ((elapsed += 5))
    done

    echo ""
    print_warning "Services may still be starting up. Check logs with:"
    echo "  docker compose -f ${compose_file} logs -f"
}

# Function to print completion message
print_completion() {
    print_header "Setup Complete!"

    echo ""
    echo "XWiki is now running with PostgreSQL and Solr."
    echo ""
    echo -e "${GREEN}Access XWiki:${NC}"
    echo "  → http://localhost:8080"
    echo ""
    echo -e "${BLUE}Solr Admin UI:${NC}"
    echo "  → http://localhost:8983/solr"
    echo ""
    echo -e "${YELLOW}Useful Commands:${NC}"
    echo "  View logs:    docker compose -f docker-compose-postgres-solr.yml logs -f"
    echo "  Stop all:     docker compose -f docker-compose-postgres-solr.yml stop"
    echo "  Start all:    docker compose -f docker-compose-postgres-solr.yml start"
    echo "  Restart all:  docker compose -f docker-compose-postgres-solr.yml restart"
    echo "  Remove all:   docker compose -f docker-compose-postgres-solr.yml down"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Open http://localhost:8080 in your browser"
    echo "  2. Complete the XWiki Distribution Wizard"
    echo "  3. Create your admin user account"
    echo "  4. Start using XWiki!"
    echo ""
    echo -e "${BLUE}Documentation:${NC}"
    echo "  → See SETUP-POSTGRES-SOLR.md for detailed documentation"
    echo ""
}

# Main function
main() {
    clear

    print_header "XWiki PostgreSQL + Solr Setup"

    echo "This script will:"
    echo "  1. Check prerequisites"
    echo "  2. Download XWiki Solr configuration"
    echo "  3. Set up file permissions"
    echo "  4. Create environment configuration"
    echo "  5. Start all Docker services"
    echo ""

    read -p "Do you want to continue? [Y/n]: " -r response
    if [[ "$response" =~ ^[Nn]$ ]]; then
        echo "Setup cancelled."
        exit 0
    fi

    # Run setup steps
    check_prerequisites

    local xwiki_version
    xwiki_version=$(get_xwiki_version)
    print_info "Selected XWiki version: ${xwiki_version}"

    download_solr_jar "${xwiki_version}" || exit 1
    set_solr_permissions || {
        print_warning "Continuing despite permission issues..."
    }
    create_env_file
    start_services || exit 1

    print_completion
}

# Run main function
main "$@"
