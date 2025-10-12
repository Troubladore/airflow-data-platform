#!/bin/bash
# Start Pagila Source Database for Layer 2 Development
# This provides a ready-to-use Pagila database for datakit testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/pagila-db.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🐘 Starting Pagila Source Database${NC}"
echo "==============================================="
echo

# Check if docker-compose or docker compose is available
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    echo -e "${RED}❌ Neither 'docker-compose' nor 'docker compose' is available${NC}"
    exit 1
fi

echo -e "${BLUE}📋 Using compose file: $COMPOSE_FILE${NC}"
echo -e "${BLUE}🚀 Starting services...${NC}"

$COMPOSE_CMD -f "$COMPOSE_FILE" up -d

echo
echo -e "${GREEN}✅ Pagila database started successfully!${NC}"
echo
echo -e "${YELLOW}📊 Connection Details:${NC}"
echo "  Image: postgres:17.5-alpine (from external pagila repo)"
echo "  Host: localhost"
echo "  Port: 15432"
echo "  Database: pagila"
echo "  Username: postgres"
echo "  Password: pagila_demo_password"
echo
echo -e "${YELLOW}💡 Note:${NC}"
echo "  This container provides the database connection only."
echo "  Pagila schema/data should be loaded from the external pagila repository."
echo "  The pagila-source datakit defines the schema contract for this data."
echo
echo -e "${YELLOW}🔧 Test Connection:${NC}"
echo "  psql -h localhost -p 15432 -U postgres -d pagila"
echo
echo -e "${YELLOW}📈 Health Check:${NC}"
echo "  $COMPOSE_CMD -f $COMPOSE_FILE logs pagila-db"
echo
echo -e "${YELLOW}🛑 Stop Database:${NC}"
echo "  $COMPOSE_CMD -f $COMPOSE_FILE down"
echo
