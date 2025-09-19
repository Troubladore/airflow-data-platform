#!/bin/bash
set -e

# Build all Docker images for Astronomer Airflow Workstation

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🏗️ Building all Docker images"
echo "=============================="
echo ""

# Ensure registry is running
if ! docker ps | grep -q registry; then
    echo "⚠️  Registry not running. Starting Traefik and Registry..."
    cd "$PROJECT_ROOT/prerequisites/traefik-registry"
    docker compose up -d
    sleep 5
    cd "$PROJECT_ROOT"
fi

# Build Layer 1: Platform Base
echo "📦 Building Layer 1: Platform Base Image"
echo "----------------------------------------"
if [ -f "$PROJECT_ROOT/layer1-platform/docker/airflow-base.Dockerfile" ]; then
    cd "$PROJECT_ROOT/layer1-platform"
    docker build -f docker/airflow-base.Dockerfile \
        -t registry.localhost/platform/airflow-base:3.0-10 .
    docker push registry.localhost/platform/airflow-base:3.0-10
    echo "✅ Platform base image built"
else
    echo "⚠️  Platform Dockerfile not found"
fi

echo ""

# Build Layer 2: Datakit Runners
echo "📦 Building Layer 2: Datakit Runners"
echo "------------------------------------"

# dbt Runner
if [ -f "$PROJECT_ROOT/layer2-datakits/dbt-runner/Dockerfile" ]; then
    echo "Building dbt-runner..."
    cd "$PROJECT_ROOT/layer2-datakits/dbt-runner"
    docker build -t registry.localhost/analytics/dbt-runner:1.0.0 .
    docker push registry.localhost/analytics/dbt-runner:1.0.0
    echo "✅ dbt-runner built"
fi

# Postgres Runner
if [ -f "$PROJECT_ROOT/layer2-datakits/postgres-runner/Dockerfile" ]; then
    echo "Building postgres-runner..."
    cd "$PROJECT_ROOT/layer2-datakits/postgres-runner"
    docker build -t registry.localhost/etl/postgres-runner:0.1.0 .
    docker push registry.localhost/etl/postgres-runner:0.1.0
    echo "✅ postgres-runner built"
fi

# SQL Server Runner
if [ -f "$PROJECT_ROOT/layer2-datakits/sqlserver-runner/Dockerfile" ]; then
    echo "Building sqlserver-runner..."
    cd "$PROJECT_ROOT/layer2-datakits/sqlserver-runner"
    docker build -t registry.localhost/etl/sqlserver-runner:0.1.0 .
    docker push registry.localhost/etl/sqlserver-runner:0.1.0
    echo "✅ sqlserver-runner built"
fi

# Spark Runner
if [ -f "$PROJECT_ROOT/layer2-datakits/spark-runner/Dockerfile" ]; then
    echo "Building spark-runner..."
    cd "$PROJECT_ROOT/layer2-datakits/spark-runner"
    docker build -t registry.localhost/etl/spark-runner:0.1.0 .
    docker push registry.localhost/etl/spark-runner:0.1.0
    echo "✅ spark-runner built"
fi

# Bronze Pagila Runner
if [ -f "$PROJECT_ROOT/layer2-datakits/bronze-pagila/Dockerfile" ]; then
    echo "Building bronze-pagila datakit..."
    cd "$PROJECT_ROOT/layer2-datakits/bronze-pagila"
    docker build -t registry.localhost/etl/datakit-bronze:0.1.0 .
    docker push registry.localhost/etl/datakit-bronze:0.1.0
    echo "✅ bronze-pagila datakit built"
fi

echo ""

# Build Kerberos Renewer if exists
if [ -f "$PROJECT_ROOT/layer1-platform-krb-renewer/Dockerfile" ]; then
    echo "📦 Building Kerberos Renewer"
    echo "----------------------------"
    cd "$PROJECT_ROOT/layer1-platform-krb-renewer"
    docker build -t registry.localhost/platform/krb-renewer:1.0.0 .
    docker push registry.localhost/platform/krb-renewer:1.0.0
    echo "✅ Kerberos renewer built"
    echo ""
fi

cd "$PROJECT_ROOT"

echo ""
echo "📊 Build Summary"
echo "----------------"
echo "✅ All available images built successfully"
echo ""
echo "Available images:"
docker images | grep registry.localhost | awk '{print "  - " $1 ":" $2}'

echo ""
echo "Next steps:"
echo "1. Verify all services: ./scripts/verify.sh"
echo "2. Start the example: cd examples/all-in-one && astro dev start"