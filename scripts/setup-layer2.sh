#!/bin/bash
# Layer 2 Data Processing Setup Script
# Builds and deploys all data processing components for development

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_HOST="registry.localhost"
IMAGE_VERSION="v1.0.0"  # Version for our built datakit images

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

print_banner() {
    echo -e "${BLUE}"
    echo "🚀 =================================================="
    echo "   LAYER 2: DATA PROCESSING COMPONENTS SETUP"
    echo "   Orchestrated Build & Deployment"
    echo "==================================================${NC}"
    echo
    echo "This script orchestrates the complete Layer 2 setup by running:"
    echo "• Phase 1: Build static components (containers & configs)"
    echo "• Phase 2: Deploy runtime components (databases & services)"
    echo "• Phase 3: Load sample data and validate setup"
    echo
    echo "For troubleshooting, you can run phases individually:"
    echo "• ./scripts/build-layer2-components.sh"
    echo "• ./scripts/deploy-layer2-runtime.sh"
    echo
}

# Component definitions
declare -A DATAKITS=(
    ["bronze-pagila"]="Raw data ingestion with audit trails"
    ["postgres-runner"]="PostgreSQL operations and utilities"
    ["spark-runner"]="Spark processing for large datasets"
    ["dbt-runner"]="DBT transformations orchestration"
    ["sqlserver-runner"]="SQL Server operations and utilities"
)

declare -A DBT_PROJECTS=(
    ["silver-core"]="Data cleaning and conformance"
    ["gold-dimensions"]="Slowly changing dimensions"
    ["gold-facts"]="Fact tables and metrics"
)

# Check prerequisites
check_prerequisites() {
    log_info "Checking Layer 1 platform prerequisites..."

    # Check if platform foundation is running
    if ! curl -k -s --connect-timeout 5 https://registry.localhost/v2/_catalog >/dev/null 2>&1; then
        log_error "Layer 1 platform foundation not running"
        log_error "Please complete Layer 1 setup first:"
        log_error "  ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml --ask-become-pass"
        exit 1
    fi

    # Check Docker availability
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running or not accessible"
        log_error "Please start Docker Desktop and ensure WSL2 integration is enabled"
        exit 1
    fi

    log_success "Platform prerequisites verified"
}

# Build data processing containers
build_datakits() {
    log_info "Building data processing containers..."

    cd "$REPO_ROOT"

    for datakit in "${!DATAKITS[@]}"; do
        log_info "Building $datakit: ${DATAKITS[$datakit]}"

        if [ ! -d "layer2-datakits/$datakit" ]; then
            log_error "Datakit directory not found: layer2-datakits/$datakit"
            continue
        fi

        # Build container
        docker build \
            -t "$REGISTRY_HOST/datakits/$datakit:latest" \
            -f "layer2-datakits/$datakit/Dockerfile" \
            "layer2-datakits/$datakit/" || {
            log_error "Failed to build $datakit"
            continue
        }

        # Push to local registry
        docker push "$REGISTRY_HOST/datakits/$datakit:latest" || {
            log_error "Failed to push $datakit to registry"
            continue
        }

        log_success "Built and pushed $datakit"
    done
}

# Setup PostgreSQL databases
setup_databases() {
    log_info "Setting up PostgreSQL databases for data processing..."

    # Create network if it doesn't exist
    docker network create data-processing-network 2>/dev/null || true

    # Source database (Pagila sample data)
    if ! docker ps --format "table {{.Names}}" | grep -q "pagila-source"; then
        log_info "Starting Pagila source database..."
        docker run -d \
            --name pagila-source \
            --network data-processing-network \
            -p 5432:5432 \
            -e POSTGRES_DB=pagila \
            -e POSTGRES_USER=postgres \
            -e POSTGRES_PASSWORD=postgres \
            -v pagila-source-data:/var/lib/postgresql/data \
            postgres:15.8

        # Wait for database to be ready
        log_info "Waiting for source database to be ready..."
        sleep 10

        # Load Pagila sample data
        log_info "Loading Pagila sample data..."
        # We'll create the sample data loading logic separately
        "$SCRIPT_DIR/load-sample-data.sh" || log_warning "Sample data loading had issues"
    else
        log_info "Pagila source database already running"
    fi

    # Target data warehouse
    if ! docker ps --format "table {{.Names}}" | grep -q "data-warehouse"; then
        log_info "Starting data warehouse database..."
        docker run -d \
            --name data-warehouse \
            --network data-processing-network \
            -p 5433:5432 \
            -e POSTGRES_DB=data_warehouse \
            -e POSTGRES_USER=warehouse \
            -e POSTGRES_PASSWORD=warehouse \
            -v data-warehouse-data:/var/lib/postgresql/data \
            postgres:15.8

        # Wait for database to be ready
        log_info "Waiting for warehouse database to be ready..."
        sleep 10

        # Initialize schemas
        log_info "Initializing data warehouse schemas..."
        docker exec data-warehouse psql -U warehouse -d data_warehouse -c "
            CREATE SCHEMA IF NOT EXISTS bronze_pagila;
            CREATE SCHEMA IF NOT EXISTS silver_core;
            CREATE SCHEMA IF NOT EXISTS gold_analytics;
            GRANT ALL ON SCHEMA bronze_pagila TO warehouse;
            GRANT ALL ON SCHEMA silver_core TO warehouse;
            GRANT ALL ON SCHEMA gold_analytics TO warehouse;
        " || log_warning "Schema initialization had issues"
    else
        log_info "Data warehouse database already running"
    fi

    log_success "Database infrastructure ready"
}

# Setup DBT projects
setup_dbt_projects() {
    log_info "Setting up DBT projects..."

    cd "$REPO_ROOT"

    # Check if DBT is available
    if ! command -v dbt >/dev/null 2>&1; then
        log_info "Installing DBT..."
        pip install --user "dbt-postgres==1.8.2" "dbt-core==1.8.2" || {
            log_error "Failed to install DBT"
            return 1
        }
    fi

    for project in "${!DBT_PROJECTS[@]}"; do
        log_info "Setting up DBT project $project: ${DBT_PROJECTS[$project]}"

        if [ ! -d "layer2-dbt-projects/$project" ]; then
            log_error "DBT project directory not found: layer2-dbt-projects/$project"
            continue
        fi

        cd "layer2-dbt-projects/$project"

        # Install DBT dependencies
        if [ -f "packages.yml" ]; then
            dbt deps || log_warning "DBT deps had issues for $project"
        fi

        # Validate DBT project
        dbt compile --target dev || log_warning "DBT compile had issues for $project"

        cd "$REPO_ROOT"
        log_success "DBT project $project configured"
    done
}

# Create Docker Compose for development
create_development_compose() {
    log_info "Creating development Docker Compose configuration..."

    cat > "$REPO_ROOT/docker-compose.layer2.yml" << 'EOF'
version: '3.8'
services:
  pagila-source:
    image: postgres:15.8
    container_name: pagila-source
    environment:
      POSTGRES_DB: pagila
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
      - pagila-source-data:/var/lib/postgresql/data
    networks:
      - data-processing

  data-warehouse:
    image: postgres:15.8
    container_name: data-warehouse
    environment:
      POSTGRES_DB: data_warehouse
      POSTGRES_USER: warehouse
      POSTGRES_PASSWORD: warehouse
    ports:
      - "5433:5432"
    volumes:
      - data-warehouse-data:/var/lib/postgresql/data
    networks:
      - data-processing

  bronze-processor:
    image: registry.localhost/datakits/bronze-pagila:latest
    container_name: bronze-processor
    depends_on:
      - pagila-source
      - data-warehouse
    networks:
      - data-processing
    environment:
      SOURCE_DB_URL: "postgresql://postgres:postgres@pagila-source:5432/pagila"
      TARGET_DB_URL: "postgresql://warehouse:warehouse@data-warehouse:5432/data_warehouse"

  dbt-runner:
    image: registry.localhost/datakits/dbt-runner:latest
    container_name: dbt-runner
    depends_on:
      - data-warehouse
    networks:
      - data-processing
    volumes:
      - ./layer2-dbt-projects:/opt/dbt/projects
    environment:
      DBT_PROFILES_DIR: /opt/dbt/profiles
      TARGET_DB_URL: "postgresql://warehouse:warehouse@data-warehouse:5432/data_warehouse"

volumes:
  pagila-source-data:
  data-warehouse-data:

networks:
  data-processing:
    external: true
EOF

    log_success "Docker Compose configuration created"
}

# Validate setup
validate_setup() {
    log_info "Validating Layer 2 setup..."

    # Check containers are running
    local containers=("pagila-source" "data-warehouse")
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}" | grep -q "$container"; then
            log_success "$container is running"
        else
            log_error "$container is not running"
            return 1
        fi
    done

    # Check registry images
    for datakit in "${!DATAKITS[@]}"; do
        if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "$REGISTRY_HOST/datakits/$datakit:latest"; then
            log_success "$datakit image available in registry"
        else
            log_error "$datakit image not found in registry"
            return 1
        fi
    done

    # Test database connectivity
    log_info "Testing database connectivity..."
    if docker exec pagila-source pg_isready -U postgres >/dev/null 2>&1; then
        log_success "Source database connectivity verified"
    else
        log_error "Source database not accessible"
        return 1
    fi

    if docker exec data-warehouse pg_isready -U warehouse >/dev/null 2>&1; then
        log_success "Warehouse database connectivity verified"
    else
        log_error "Warehouse database not accessible"
        return 1
    fi

    log_success "Layer 2 setup validation passed"
}

# Show next steps
show_next_steps() {
    echo
    echo -e "${GREEN}🎉 Layer 2 Data Processing Setup Complete!${NC}"
    echo
    echo -e "${BLUE}📊 What's Available:${NC}"
    echo "• Source Database: postgresql://postgres:postgres@localhost:5432/pagila"
    echo "• Data Warehouse: postgresql://warehouse:warehouse@localhost:5433/data_warehouse"
    echo "• Container Images: Available in registry.localhost/datakits/*"
    echo "• DBT Projects: Configured and ready in layer2-dbt-projects/"
    echo
    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo "1. Load sample data:"
    echo "   ./scripts/load-sample-data.sh"
    echo
    echo "2. Run end-to-end data pipeline:"
    echo "   ./scripts/run-data-pipeline.sh --full-refresh"
    echo
    echo "3. Validate data processing:"
    echo "   ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-layer2-data.yml --ask-become-pass"
    echo
    echo "4. Test individual components:"
    echo "   ./scripts/test-datakit.sh bronze-pagila"
    echo
    echo -e "${YELLOW}💡 Development Workflow:${NC}"
    echo "• Use docker-compose.layer2.yml for container management"
    echo "• See README-LAYER2-DATA-PROCESSING.md for detailed usage"
    echo "• Use ./scripts/teardown-layer2.sh for clean testing"
    echo
}

# Parse command line arguments
REBUILD_IMAGES=false
FORCE_DB_RECREATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --rebuild-images)
            REBUILD_IMAGES=true
            shift
            ;;
        --force-db-recreate)
            FORCE_DB_RECREATE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --rebuild-images       Force rebuild of all container images"
            echo "  --force-db-recreate    Force recreation of databases (data loss!)"
            echo "  -h, --help            Show this help"
            exit 0
            ;;
        *)
            log_warning "Unknown option: $1"
            shift
            ;;
    esac
done

# Main execution - orchestrates phases
main() {
    print_banner
    check_prerequisites

    local setup_success=true
    local build_options=""
    local deploy_options=""

    # Prepare options for sub-scripts
    if [ "$REBUILD_IMAGES" = true ]; then
        build_options="$build_options --force-rebuild"
    fi

    if [ "$FORCE_DB_RECREATE" = true ]; then
        deploy_options="$deploy_options --force-recreate"
    fi

    # Phase 1: Build static components
    log_info "🔨 Phase 1: Building static components..."
    if "$SCRIPT_DIR/build-layer2-components.sh" $build_options; then
        log_success "Phase 1 completed: Static components built"
    else
        log_error "Phase 1 failed: Static component build issues"
        setup_success=false
    fi

    echo

    # Phase 2: Deploy runtime components (only if Phase 1 succeeded)
    if [ "$setup_success" = true ]; then
        log_info "🚀 Phase 2: Deploying runtime components..."
        if "$SCRIPT_DIR/deploy-layer2-runtime.sh" $deploy_options; then
            log_success "Phase 2 completed: Runtime components deployed"
        else
            log_error "Phase 2 failed: Runtime deployment issues"
            setup_success=false
        fi
    else
        log_warning "Skipping Phase 2 due to Phase 1 failures"
    fi

    echo

    # Phase 3: Final validation (only if previous phases succeeded)
    if [ "$setup_success" = true ]; then
        log_info "🔍 Phase 3: Final validation and setup completion..."
        validate_setup || setup_success=false
    else
        log_warning "Skipping Phase 3 due to previous phase failures"
    fi

    # Show results
    if [ "$setup_success" = true ]; then
        show_next_steps
        return 0
    else
        echo
        log_error "❌ Layer 2 setup failed during one or more phases!"
        echo
        echo -e "${RED}Troubleshooting Steps:${NC}"
        echo "1. Run phases individually to isolate issues:"
        echo "   ./scripts/build-layer2-components.sh --build-optional"
        echo "   ./scripts/deploy-layer2-runtime.sh --skip-sample-data"
        echo
        echo "2. Check specific component logs:"
        echo "   ls /tmp/build_*.log"
        echo "   docker logs <container-name>"
        echo
        echo "3. Clean restart if needed:"
        echo "   ./scripts/teardown-layer2.sh --preserve-data"
        echo
        return 1
    fi
}

# Handle script errors
trap 'log_error "Layer 2 setup failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"
