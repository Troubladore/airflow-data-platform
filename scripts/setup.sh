#!/bin/bash
set -e

# Astronomer Airflow Data Engineering Workstation Setup
# Complete automated setup for local development environment

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🚀 Astronomer Airflow Workstation Setup"
echo "========================================"
echo ""

# Check prerequisites
check_prerequisites() {
    echo "📋 Checking prerequisites..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker not found. Please install Docker Desktop or Docker Engine."
        exit 1
    fi

    # Check Docker daemon
    if ! docker info &> /dev/null; then
        echo "❌ Docker daemon not running. Please start Docker."
        exit 1
    fi

    echo "✅ Docker is installed and running"

    # Check for WSL2 if on Windows
    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "🪟 WSL2 environment detected"
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
        curl -sSL install.astronomer.io | sudo bash -s
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

    check_prerequisites
    install_base_packages
    install_astro_cli
    setup_hosts
    create_docker_network
    setup_certificates
    setup_traefik_registry
    build_platform_image

    echo ""
    echo "✨ Setup complete!"
    echo ""
    echo "Next steps:"
    echo "1. Review the documentation in docs/"
    echo "2. Start with the examples in examples/all-in-one"
    echo "3. Customize warehouse configurations in layer3-warehouses/configs/"
    echo ""
    echo "To verify the installation:"
    echo "  ./scripts/verify.sh"
    echo ""
    echo "To start the development environment:"
    echo "  cd examples/all-in-one && astro dev start"
}

main "$@"