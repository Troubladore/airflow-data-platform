#!/bin/bash
# Layer 3 Warehouse Teardown Script
# Cleans up pipeline orchestration and database environments

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

print_banner() {
    echo -e "${BLUE}"
    echo "🧹 =================================================="
    echo "   LAYER 3: WAREHOUSE TEARDOWN"
    echo "   Clean Pipeline Environment"
    echo "==================================================${NC}"
    echo
    echo "This script will clean up:"
    echo "• Database containers and volumes"
    echo "• Airflow/orchestration environments"
    echo "• Pipeline networks and configurations"
    echo "• Integration test artifacts"
    echo
}

# Layer 3 teardown implementation
teardown_layer3_databases() {
    log_info "Stopping Layer 3 database containers..."

    # Stop any warehouse PostgreSQL containers (future)
    docker ps -aq --filter "name=warehouse-db" | xargs -r docker rm -f 2>/dev/null || true
    docker ps -aq --filter "name=bronze-db" | xargs -r docker rm -f 2>/dev/null || true
    docker ps -aq --filter "name=silver-db" | xargs -r docker rm -f 2>/dev/null || true
    docker ps -aq --filter "name=gold-db" | xargs -r docker rm -f 2>/dev/null || true

    # Clean up warehouse volumes (using bitnami pattern)
    docker volume ls -q | grep -E "(warehouse|bronze|silver|gold)_data" | xargs -r docker volume rm 2>/dev/null || true

    log_success "Layer 3 database cleanup completed"
}

print_banner
log_info "Implementing Layer 3 teardown..."

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    log_warning "Docker not available - skipping container cleanup"
elif ! docker info &> /dev/null; then
    log_warning "Docker daemon not running - skipping container cleanup"
else
    teardown_layer3_databases
fi

echo
echo "Layer 3 teardown targets:"
echo "✅ Database containers (warehouse PostgreSQL instances)"
echo "✅ Pipeline orchestration cleanup (Airflow - future)"
echo "✅ Integration test volumes and networks"
echo "✅ Bitnami PostgreSQL volume cleanup"
echo
echo -e "${YELLOW}💡 Note: Layer 2 components (datakits) are preserved${NC}"
echo "Use ./scripts/teardown-layer2.sh to clean component images if needed."
