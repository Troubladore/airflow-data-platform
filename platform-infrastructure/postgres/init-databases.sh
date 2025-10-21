#!/bin/bash
# Platform PostgreSQL - Multi-Database Initialization
# ====================================================
# Creates databases for platform services (OLTP workloads)
# Runs once on first container startup
#
# Architecture:
# - One PostgreSQL instance with multiple databases
# - Matches production pattern (RDS with multiple DBs)
# - Separate from warehouse PostgreSQL (OLAP workloads)
#
# Databases Created:
# - openmetadata_db: OpenMetadata metadata storage
# - airflow_db (future): Airflow metastore
# - [Add new platform services here as needed]

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Initializing Platform PostgreSQL Databases"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================
# 1. OpenMetadata Database
# ============================================
echo "Creating OpenMetadata database..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    -- Create user (credentials from platform-bootstrap/.env)
    CREATE USER ${OPENMETADATA_DB_USER:-openmetadata_user} WITH PASSWORD '${OPENMETADATA_DB_PASSWORD:-changeme}';

    -- Create database
    CREATE DATABASE openmetadata_db OWNER ${OPENMETADATA_DB_USER:-openmetadata_user};

    -- Grant privileges
    GRANT ALL PRIVILEGES ON DATABASE openmetadata_db TO ${OPENMETADATA_DB_USER:-openmetadata_user};

    -- Connect and set up extensions if needed
    \c openmetadata_db

    -- Enable UUID extension (useful for OpenMetadata)
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

    -- Grant schema privileges
    GRANT ALL ON SCHEMA public TO ${OPENMETADATA_DB_USER:-openmetadata_user};
EOSQL

echo "✓ OpenMetadata database created (openmetadata_db)"
echo ""

# ============================================
# 2. Future: Airflow Metastore Database
# ============================================
# Uncomment when ready to use shared PostgreSQL for Airflow
#
# echo "Creating Airflow database..."
# psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
#     CREATE USER airflow_user WITH PASSWORD '${AIRFLOW_DB_PASSWORD:-changeme_airflow_password}';
#     CREATE DATABASE airflow_db OWNER airflow_user;
#     GRANT ALL PRIVILEGES ON DATABASE airflow_db TO airflow_user;
# EOSQL
# echo "✓ Airflow database created (airflow_db)"
# echo ""

# ============================================
# 3. Future: Add Other Platform Services
# ============================================
# Pattern for adding new platform services:
#
# echo "Creating [service] database..."
# psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
#     CREATE USER [service]_user WITH PASSWORD '${SERVICE_DB_PASSWORD}';
#     CREATE DATABASE [service]_db OWNER [service]_user;
#     GRANT ALL PRIVILEGES ON DATABASE [service]_db TO [service]_user;
# EOSQL

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Platform databases initialized successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Summary:"
echo "  ✓ openmetadata_db (user: openmetadata_user)"
echo "  • airflow_db (future - uncomment when ready)"
echo "  • [add more platform services as needed]"
echo ""
echo "Note: This is for platform OLTP workloads only."
echo "      Warehouse (OLAP) databases are separate instances."
echo ""
