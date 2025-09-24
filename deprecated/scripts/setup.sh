#!/bin/bash
set -e

# Astronomer Airflow Data Engineering Workstation Setup
# Complete automated setup for local development environment

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Astronomer Airflow Workstation Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}⚡ New: Ansible-powered automation with graceful admin handling${NC}"
echo ""

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Check for Ansible automation
check_ansible_setup() {
    log_info "Checking for modern Ansible automation..."

    if [ -f "$PROJECT_ROOT/ansible/site.yml" ]; then
        if command -v ansible-playbook &> /dev/null; then
            log_success "Ansible automation available!"
            echo
            echo -e "${GREEN}🎯 Recommended: Use Ansible for robust, automated setup${NC}"
            echo
            echo "Full setup with graceful admin handling:"
            echo "  cd $PROJECT_ROOT"
            echo "  ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml"
            echo
            echo "Validation after setup:"
            echo "  ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-all.yml"
            echo
            echo "Complete teardown for testing:"
            echo "  ./scripts/teardown.sh"
            echo
            read -p "Use Ansible automation? (Y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                log_info "Starting Ansible automation..."
                cd "$PROJECT_ROOT"
                exec ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml
            fi
        else
            log_warning "Ansible automation available but not installed"
            echo
            echo "To use the improved automation:"
            echo "  # 🐧 Install pipx for isolated Python tools"
            echo "  sudo apt update && sudo apt install -y pipx"
            echo "  pipx ensurepath"
            echo "  # Install pinned dependencies"
            echo "  ./scripts/install-pipx-deps.sh"
            echo "  ansible-galaxy install -r ansible/requirements.yml"
            echo "  # Run automation"
            echo "  ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml"
            echo
            echo "Continuing with legacy manual setup..."
            echo
        fi
    else
        log_warning "Ansible automation not found, using legacy setup"
        echo
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker Desktop or Docker Engine."
        exit 1
    fi

    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon not running. Please start Docker."
        exit 1
    fi

    log_success "Docker is installed and running"

    # Check for WSL2 if on Windows
    if grep -qi microsoft /proc/version 2>/dev/null; then
        log_info "WSL2 environment detected"
    fi

    echo ""
}

# Install base packages
install_base_packages() {
    echo "📦 Installing base packages..."

    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y \
            build-essential curl git unzip ca-certificates \
            libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
            libffi-dev postgresql-client jq
    elif command -v brew &> /dev/null; then
        brew install curl git unzip postgresql jq
    else
        echo "⚠️  Unsupported package manager. Please install dependencies manually."
    fi

    echo "✅ Base packages installed"
    echo ""
}

# Install Astronomer CLI
install_astro_cli() {
    echo "🚀 Installing Astronomer CLI..."

    if ! command -v astro &> /dev/null; then
        # Secure Astro CLI installation (avoiding pipe-to-shell)
        echo "Installing Astro CLI securely..."
        ASTRO_URL=$(curl -s https://api.github.com/repos/astronomer/astro-cli/releases/latest | grep "browser_download_url.*linux_amd64.tar.gz" | cut -d '"' -f 4)
        wget -O /tmp/astro-cli.tar.gz "$ASTRO_URL"
        sudo tar -xzf /tmp/astro-cli.tar.gz -C /usr/local/bin --strip-components=0 astro
        sudo chmod +x /usr/local/bin/astro
        rm -f /tmp/astro-cli.tar.gz
    fi

    astro version
    echo "✅ Astronomer CLI installed"
    echo ""
}

# Setup hosts file entries
setup_hosts() {
    echo "🌐 Setting up local hosts..."

    HOSTS_ENTRIES="127.0.0.1       registry.localhost
127.0.0.1       traefik.localhost
127.0.0.1       whoami.localhost
127.0.0.1       airflow-dev.customer.localhost"

    # Check if entries already exist
    if ! grep -q "registry.localhost" /etc/hosts; then
        echo "Adding hosts entries (requires sudo)..."
        echo "$HOSTS_ENTRIES" | sudo tee -a /etc/hosts > /dev/null
        echo "✅ Hosts file updated"
    else
        echo "✅ Hosts entries already exist"
    fi

    echo ""
}

# Create Docker network
create_docker_network() {
    echo "🔗 Creating Docker network..."

    if ! docker network ls | grep -q "edge"; then
        docker network create edge
        echo "✅ Docker network 'edge' created"
    else
        echo "✅ Docker network 'edge' already exists"
    fi

    echo ""
}

# Setup TLS certificates
setup_certificates() {
    echo "🔐 Setting up TLS certificates..."

    CERT_DIR="$PROJECT_ROOT/prerequisites/certificates/certs"
    mkdir -p "$CERT_DIR"

    # For now, create self-signed certificates
    # In production, use mkcert or proper CA
    if [ ! -f "$CERT_DIR/cert.pem" ]; then
        openssl req -x509 -newkey rsa:4096 -nodes \
            -keyout "$CERT_DIR/key.pem" \
            -out "$CERT_DIR/cert.pem" \
            -days 365 \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=*.localhost"
        echo "✅ Self-signed certificates created"
    else
        echo "✅ Certificates already exist"
    fi

    echo ""
}

# Build and start Traefik + Registry
setup_traefik_registry() {
    echo "🚦 Setting up Traefik and Registry..."

    cd "$PROJECT_ROOT/prerequisites/traefik-registry"

    # We'll create the docker-compose file in the next step
    if [ -f "docker-compose.yml" ]; then
        docker compose up -d
        echo "✅ Traefik and Registry started"

        # Test registry
        sleep 5
        docker pull busybox
        docker tag busybox registry.localhost/test/busybox:latest
        if docker push registry.localhost/test/busybox:latest; then
            echo "✅ Registry test successful"
        else
            echo "⚠️  Registry test failed - check configuration"
        fi
    else
        echo "⚠️  Traefik configuration not found - will be created in next steps"
    fi

    cd "$PROJECT_ROOT"
    echo ""
}

# Build platform base image
build_platform_image() {
    echo "🏗️ Building platform base image..."

    if [ -d "$PROJECT_ROOT/layer1-platform/docker" ]; then
        cd "$PROJECT_ROOT/layer1-platform"

        if [ -f "docker/airflow-base.Dockerfile" ]; then
            docker build -f docker/airflow-base.Dockerfile \
                -t registry.localhost/platform/airflow-base:3.0-10 .

            docker push registry.localhost/platform/airflow-base:3.0-10
            echo "✅ Platform base image built and pushed"
        else
            echo "⚠️  Platform Dockerfile will be created in next steps"
        fi
    else
        echo "⚠️  Platform configuration will be set up in next steps"
    fi

    cd "$PROJECT_ROOT"
    echo ""
}

# Main setup flow
main() {
    echo "Starting setup at $(date)"
    echo "Project root: $PROJECT_ROOT"
    echo ""

    # Check for modern Ansible automation first
    check_ansible_setup

    # If we reach here, user chose legacy setup or Ansible not available
    log_info "Proceeding with legacy manual setup..."
    echo

    check_prerequisites
    install_base_packages
    install_astro_cli
    setup_hosts
    create_docker_network
    setup_certificates
    setup_traefik_registry
    build_platform_image

    echo ""
    log_success "Legacy setup complete!"
    echo ""
    echo "Next steps:"
    echo "1. Review the documentation in docs/"
    echo "2. Start with the examples in examples/all-in-one"
    echo "3. Customize warehouse configurations in layer3-warehouses/configs/"
    echo ""
    echo "To verify the installation:"
    echo "  ./scripts/verify.sh"
    echo ""
    echo "To teardown and test rebuild:"
    echo "  ./scripts/teardown.sh"
    echo ""
    echo "To start the development environment:"
    echo "  cd examples/all-in-one && astro dev start"
    echo ""
    echo -e "${YELLOW}💡 Consider upgrading to Ansible automation for improved reliability!${NC}"
}

main "$@"
