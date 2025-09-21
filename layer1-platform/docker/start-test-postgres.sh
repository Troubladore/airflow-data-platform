#!/bin/bash
# Start PostgreSQL Test Sandbox for Datakit Testing
# Ephemeral database for testing bronze table deployments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/test-postgres.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🧪 Starting PostgreSQL Test Sandbox${NC}"
echo "======================================="
echo

# Check if docker-compose or docker compose is available
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    echo -e "${RED}❌ Neither 'docker-compose' nor 'docker compose' is available${NC}"
    echo "This testing sandbox requires Docker. Please install Docker Desktop with WSL2 integration."
    exit 1
fi

echo -e "${BLUE}🚀 Starting test database...${NC}"
$COMPOSE_CMD -f "$COMPOSE_FILE" up -d

echo
echo -e "${GREEN}✅ Test PostgreSQL sandbox started!${NC}"
echo
echo -e "${YELLOW}🧪 Test Database Details:${NC}"
echo "  Image: bitnami/postgresql:17.2.0 (269MB - optimized for security)"
echo "  Host: localhost"
echo "  Port: 15444"
echo "  Database: datakit_tests"
echo "  Username: test_user"
echo "  Authentication: empty password (no password required for local development)"
echo
echo -e "${YELLOW}🔧 Test Connection:${NC}"
echo "  psql -h localhost -p 15444 -U test_user -d datakit_tests"
echo
echo -e "${YELLOW}🚀 Deploy Bronze Tables:${NC}"
echo "  cd ../../data-workspace"
echo "  uv run python data-platform-framework/scripts/deploy_datakit.py \\"
echo "    ../layer2-datakits/pagila-bronze --target postgres_local \\"
echo "    --host localhost --port 15444 --database datakit_tests \\"
echo "    --user test_user --validate"
echo
echo -e "${YELLOW}🛑 Stop Test Sandbox:${NC}"
echo "  $COMPOSE_CMD -f $COMPOSE_FILE down"
echo
echo -e "${GREEN}💡 Note: This is an ephemeral test database.${NC}"
echo "Data is lost when stopped (intentional for clean testing)."
echo
