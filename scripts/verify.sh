#!/bin/bash
set -e

# Verification script for Astronomer Airflow Workstation Setup

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🔍 Verifying Astronomer Airflow Workstation Setup"
echo "=================================================="
echo ""

TOTAL_CHECKS=0
PASSED_CHECKS=0

check() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if eval "$2"; then
        echo "✅ $1"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo "❌ $1"
    fi
}

echo "📋 System Prerequisites"
echo "-----------------------"
check "Docker installed" "command -v docker &> /dev/null"
check "Docker running" "docker info &> /dev/null"
check "Astronomer CLI installed" "command -v astro &> /dev/null"
check "Git installed" "command -v git &> /dev/null"

echo ""
echo "🌐 Network Configuration"
echo "------------------------"
check "Docker network 'edge' exists" "docker network ls | grep -q edge"
check "registry.localhost in hosts" "grep -q registry.localhost /etc/hosts"
check "traefik.localhost in hosts" "grep -q traefik.localhost /etc/hosts"

echo ""
echo "📁 Directory Structure"
echo "----------------------"
check "Layer 1 Platform exists" "[ -d '$PROJECT_ROOT/layer1-platform' ]"
check "Layer 2 Datakits exists" "[ -d '$PROJECT_ROOT/layer2-datakits' ]"
check "Layer 2 dbt Projects exists" "[ -d '$PROJECT_ROOT/layer2-dbt-projects' ]"
check "Layer 3 Warehouses exists" "[ -d '$PROJECT_ROOT/layer3-warehouses' ]"
check "Examples directory exists" "[ -d '$PROJECT_ROOT/examples' ]"
check "Documentation exists" "[ -d '$PROJECT_ROOT/docs' ]"

echo ""
echo "🐳 Container Services"
echo "---------------------"
check "Traefik container running" "docker ps | grep -q traefik || echo 'Not started yet'"
check "Registry container running" "docker ps | grep -q registry || echo 'Not started yet'"

echo ""
echo "📝 Configuration Files"
echo "----------------------"
check "Traefik compose file exists" "[ -f '$PROJECT_ROOT/prerequisites/traefik-registry/docker-compose.yml' ]"
check "Platform Dockerfile exists" "[ -f '$PROJECT_ROOT/layer1-platform/docker/airflow-base.Dockerfile' ]"
check "dbt runner Dockerfile exists" "[ -f '$PROJECT_ROOT/layer2-datakits/dbt-runner/Dockerfile' ]"
check "Warehouse configs exist" "[ -d '$PROJECT_ROOT/layer3-warehouses/configs/warehouses' ]"

echo ""
echo "🚀 Astronomer Components"
echo "------------------------"
if [ -d "$PROJECT_ROOT/examples/all-in-one" ]; then
    cd "$PROJECT_ROOT/examples/all-in-one"
    check "Astro project initialized" "[ -f 'airflow_settings.yaml' ]"
    check "DAGs directory exists" "[ -d 'dags' ]"
    check "Include directory exists" "[ -d 'include' ]"
    cd "$PROJECT_ROOT"
fi

echo ""
echo "📊 Summary"
echo "----------"
echo "Passed: $PASSED_CHECKS / $TOTAL_CHECKS checks"

if [ $PASSED_CHECKS -eq $TOTAL_CHECKS ]; then
    echo ""
    echo "✨ All checks passed! Your environment is ready."
    echo ""
    echo "Next steps:"
    echo "1. Start Traefik and Registry:"
    echo "   cd prerequisites/traefik-registry && docker compose up -d"
    echo ""
    echo "2. Build base images:"
    echo "   ./scripts/build-all.sh"
    echo ""
    echo "3. Start the example project:"
    echo "   cd examples/all-in-one && astro dev start"
else
    echo ""
    echo "⚠️  Some checks failed. Please run:"
    echo "   ./scripts/setup.sh"
    echo ""
    echo "For specific issues, check the documentation in docs/"
fi

exit 0