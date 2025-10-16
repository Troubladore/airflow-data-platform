# OpenMetadata Implementation Specification

**Status:** Technical Specification
**Date:** 2025-01-16
**Prerequisites:** [OpenMetadata Integration Design](openmetadata-integration-design.md)

---

## Purpose

This document provides step-by-step implementation instructions for integrating OpenMetadata with the Airflow Data Platform. Follow the phases sequentially to ensure proper integration and validation at each step.

---

## Prerequisites

Before starting implementation:

- [ ] Read [OpenMetadata Integration Design](openmetadata-integration-design.md)
- [ ] Platform Bootstrap services working (`make platform-start`)
- [ ] Kerberos sidecar tested and operational
- [ ] Docker Desktop with at least 8GB RAM allocated
- [ ] PostgreSQL test database (pagila) available

---

## Phase 1: Proof of Concept (Pagila Schema Harvesting)

**Timeline:** 1-2 days
**Goal:** Demonstrate OpenMetadata can harvest metadata from PostgreSQL

### Step 1.1: Create Docker Compose Configuration

Create `platform-bootstrap/docker-compose.openmetadata.yml`:

```yaml
# OpenMetadata Stack - Extends base docker-compose.yml
# Usage: docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml up -d

version: "3.8"

services:
  # ============================================
  # OpenMetadata PostgreSQL (Metadata Database)
  # ============================================
  openmetadata-postgres:
    image: ${IMAGE_POSTGRES:-postgres:15}
    container_name: openmetadata-postgres
    restart: unless-stopped

    environment:
      POSTGRES_USER: openmetadata_user
      POSTGRES_PASSWORD: ${OPENMETADATA_DB_PASSWORD:-openmetadata_pass}
      POSTGRES_DB: openmetadata_db

    volumes:
      - openmetadata_postgres_data:/var/lib/postgresql/data

    networks:
      - platform-net

    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U openmetadata_user -d openmetadata_db"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ============================================
  # Elasticsearch (Search & Indexing)
  # ============================================
  openmetadata-elasticsearch:
    image: ${IMAGE_ELASTICSEARCH:-docker.elastic.co/elasticsearch/elasticsearch:8.10.2}
    container_name: openmetadata-elasticsearch
    restart: unless-stopped

    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - ES_JAVA_OPTS=-Xms1g -Xmx1g

    volumes:
      - openmetadata_es_data:/usr/share/elasticsearch/data

    networks:
      - platform-net

    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:9200/_cluster/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5

  # ============================================
  # OpenMetadata Server (Core Application)
  # ============================================
  openmetadata-server:
    image: ${IMAGE_OPENMETADATA_SERVER:-docker.getcollate.io/openmetadata/server:1.2.0}
    container_name: openmetadata-server
    restart: unless-stopped

    ports:
      - "${OPENMETADATA_PORT:-8585}:8585"

    environment:
      # Database configuration
      DB_DRIVER_CLASS: org.postgresql.Driver
      DB_URL: jdbc:postgresql://openmetadata-postgres:5432/openmetadata_db
      DB_USER: openmetadata_user
      DB_USER_PASSWORD: ${OPENMETADATA_DB_PASSWORD:-openmetadata_pass}

      # Elasticsearch configuration
      ELASTICSEARCH_HOST: openmetadata-elasticsearch
      ELASTICSEARCH_PORT: 9200

      # OpenMetadata configuration
      OPENMETADATA_CLUSTER_NAME: ${OPENMETADATA_CLUSTER_NAME:-local-dev}
      SERVER_HOST_API_URL: http://localhost:8585/api

      # Authentication (basic for local development)
      AUTHENTICATION_PROVIDER: basic
      AUTHENTICATION_PUBLIC_KEYS: []

      # Pipeline service client
      PIPELINE_SERVICE_CLIENT_ENABLED: true
      PIPELINE_SERVICE_CLIENT_CLASS_NAME: org.openmetadata.service.clients.pipeline.airflow.AirflowRESTClient
      SERVER_HOST: openmetadata-server

    depends_on:
      openmetadata-postgres:
        condition: service_healthy
      openmetadata-elasticsearch:
        condition: service_healthy

    networks:
      - platform-net

    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8585/api/v1/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 10

  # ============================================
  # OpenMetadata Ingestion (Metadata Harvesting)
  # ============================================
  openmetadata-ingestion:
    image: ${IMAGE_OPENMETADATA_INGESTION:-docker.getcollate.io/openmetadata/ingestion:1.2.0}
    container_name: openmetadata-ingestion
    restart: unless-stopped

    ports:
      - "${OPENMETADATA_INGESTION_PORT:-8080}:8080"

    environment:
      # Airflow configuration
      AIRFLOW__API__AUTH_BACKENDS: airflow.api.auth.backend.basic_auth
      AIRFLOW__CORE__EXECUTOR: LocalExecutor
      AIRFLOW__CORE__LOAD_EXAMPLES: false
      AIRFLOW__CORE__DAGS_FOLDER: /opt/airflow/dags

      # OpenMetadata configuration
      AIRFLOW_HOME: /opt/airflow
      OPENMETADATA_SERVER_URL: http://openmetadata-server:8585/api
      OPENMETADATA_CLUSTER_NAME: ${OPENMETADATA_CLUSTER_NAME:-local-dev}

      # Kerberos configuration (Phase 2)
      # KRB5CCNAME: /krb5/cache/krb5cc
      # KRB5_CONFIG: /etc/krb5.conf

    volumes:
      # Kerberos integration (uncomment in Phase 2)
      # - platform_kerberos_cache:/krb5/cache:ro
      # - ${KRB5_CONF_PATH:-/etc/krb5.conf}:/etc/krb5.conf:ro

      # Custom ingestion DAGs (optional)
      - ./openmetadata/dags:/opt/airflow/dags:rw

    depends_on:
      openmetadata-server:
        condition: service_healthy

    networks:
      - platform-net

volumes:
  openmetadata_postgres_data:
    name: openmetadata_postgres_data
  openmetadata_es_data:
    name: openmetadata_es_data

networks:
  platform-net:
    external: true
    name: platform_network
```

**Key Configuration Notes:**
- Uses `platform-net` (existing network)
- Does NOT mount Kerberos volume yet (Phase 2)
- Exposes UI on port 8585, Ingestion on 8080
- Health checks ensure proper startup ordering

### Step 1.2: Update Environment Variables

Add to `platform-bootstrap/.env.example`:

```bash
# ============================================
# OpenMetadata Configuration
# ============================================

# Server
OPENMETADATA_PORT=8585
OPENMETADATA_CLUSTER_NAME=local-dev

# Images (customize for corporate Artifactory)
IMAGE_OPENMETADATA_SERVER=docker.getcollate.io/openmetadata/server:1.2.0
IMAGE_OPENMETADATA_INGESTION=docker.getcollate.io/openmetadata/ingestion:1.2.0
IMAGE_ELASTICSEARCH=docker.elastic.co/elasticsearch/elasticsearch:8.10.2
IMAGE_POSTGRES=postgres:15

# Database (CHANGE THIS - generate secure password!)
OPENMETADATA_DB_PASSWORD=changeme_secure_password

# Ingestion Airflow
OPENMETADATA_INGESTION_PORT=8080
```

Then copy to actual `.env` file:

```bash
cd platform-bootstrap
cp .env.example .env
# Edit .env and change OPENMETADATA_DB_PASSWORD to something secure
```

### Step 1.3: Update Makefile

**Decision:** OpenMetadata is an **always-on service** (like Kerberos sidecar)

This means `make platform-start` will start OpenMetadata automatically.

Add OpenMetadata targets to `platform-bootstrap/Makefile`:

```makefile
# ============================================
# OpenMetadata Management
# ============================================

# Note: platform-start now includes OpenMetadata (always-on)
.PHONY: platform-start
platform-start: network-create volumes-create ## Start all platform services (Kerberos + OpenMetadata)
	@echo "$(CYAN)Starting platform services...$(NC)"
	@docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml up -d
	@echo ""
	@echo "$(GREEN)Platform services starting...$(NC)"
	@echo ""
	@echo "Kerberos Sidecar:"
	@echo "  Status: docker ps | grep kerberos-platform-service"
	@echo ""
	@echo "OpenMetadata:"
	@echo "  UI:        http://localhost:8585"
	@echo "  Ingestion: http://localhost:8080"
	@echo "  Login:     admin@open-metadata.org / admin"
	@echo ""
	@echo "$(YELLOW)Note: First startup may take 2-3 minutes$(NC)"

.PHONY: openmetadata-only
openmetadata-only: ## Start only OpenMetadata (without Kerberos)
	@echo "$(CYAN)Starting OpenMetadata stack...$(NC)"
	@docker compose -f docker-compose.openmetadata.yml up -d
	@echo "$(GREEN)OpenMetadata started$(NC)"

.PHONY: openmetadata-stop
openmetadata-stop: ## Stop OpenMetadata services
	@echo "$(CYAN)Stopping OpenMetadata stack...$(NC)"
	@docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml down
	@echo "$(GREEN)OpenMetadata stopped$(NC)"

.PHONY: openmetadata-status
openmetadata-status: ## Check OpenMetadata services status
	@echo "$(CYAN)OpenMetadata Services Status:$(NC)"
	@echo "=============================="
	@docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml ps
	@echo ""
	@echo "Health checks:"
	@echo -n "  OpenMetadata Server: "
	@if curl -sf http://localhost:8585/api/v1/health >/dev/null 2>&1; then \
		echo "$(GREEN)✓ Healthy$(NC)"; \
	else \
		echo "$(RED)✗ Unhealthy$(NC)"; \
	fi
	@echo -n "  Ingestion Airflow:   "
	@if curl -sf http://localhost:8080/health >/dev/null 2>&1; then \
		echo "$(GREEN)✓ Healthy$(NC)"; \
	else \
		echo "$(RED)✗ Unhealthy$(NC)"; \
	fi

.PHONY: openmetadata-logs
openmetadata-logs: ## Show OpenMetadata logs (follow mode)
	@docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml logs -f

.PHONY: openmetadata-clean
openmetadata-clean: ## Remove OpenMetadata data (WARNING: deletes all metadata!)
	@echo "$(RED)WARNING: This will delete ALL OpenMetadata data!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml down -v; \
		echo "$(GREEN)OpenMetadata data deleted$(NC)"; \
	else \
		echo "Cancelled"; \
	fi
```

Also update the main `help` target to include OpenMetadata:

```makefile
.PHONY: help
help: ## Show this help message
	@echo "$(BOLD)Platform Bootstrap - Service Management$(NC)"
	@echo ""
	@echo "$(CYAN)Core Services:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		grep -v "openmetadata-" | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(CYAN)OpenMetadata (Optional):$(NC)"
	@grep -E '^openmetadata-[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-20s$(NC) %s\n", $$1, $$2}'
```

### Step 1.4: Create OpenMetadata DAGs Directory

```bash
mkdir -p platform-bootstrap/openmetadata/dags
cat > platform-bootstrap/openmetadata/dags/.gitkeep <<EOF
# Custom OpenMetadata ingestion DAGs go here
# The ingestion container will mount this directory
EOF
```

### Step 1.5: Test Basic Startup

```bash
cd platform-bootstrap

# Start OpenMetadata
make openmetadata-start

# Wait for services to initialize (2-3 minutes)
# Monitor startup
make openmetadata-logs

# Check status
make openmetadata-status
```

**Expected Output:**
```
OpenMetadata Services Status:
==============================
NAME                           STATUS    PORTS
openmetadata-postgres          Up        5432/tcp (healthy)
openmetadata-elasticsearch     Up        9200/tcp, 9300/tcp (healthy)
openmetadata-server            Up        0.0.0.0:8585->8585/tcp (healthy)
openmetadata-ingestion         Up        0.0.0.0:8080->8080/tcp

Health checks:
  OpenMetadata Server: ✓ Healthy
  Ingestion Airflow:   ✓ Healthy
```

### Step 1.6: Access OpenMetadata UI

1. Open browser: http://localhost:8585
2. Login with:
   - Email: `admin@open-metadata.org`
   - Password: `admin`
3. You should see the OpenMetadata dashboard

### Step 1.7: Create Pagila PostgreSQL Connection

**Important:** For Phase 1, use a local or accessible PostgreSQL with pagila database.

Setup pagila (if not already done):

```bash
# Option 1: Use Docker PostgreSQL
docker run -d \
  --name pagila-postgres \
  --network platform_network \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  postgres:15

# Download pagila schema
cd /tmp
wget https://github.com/devrimgunduz/pagila/raw/master/pagila-schema.sql
wget https://github.com/devrimgunduz/pagila/raw/master/pagila-data.sql

# Load pagila
docker exec -i pagila-postgres psql -U postgres < pagila-schema.sql
docker exec -i pagila-postgres psql -U postgres < pagila-data.sql

# Verify
docker exec pagila-postgres psql -U postgres -d pagila -c "\dt"
```

In OpenMetadata UI:

1. Click "Settings" → "Services" → "Databases"
2. Click "+ Add Database"
3. Select "Postgres"
4. Configure connection:
   ```
   Name: pagila-local
   Host: pagila-postgres (or host.docker.internal for localhost)
   Port: 5432
   Username: postgres
   Password: postgres
   Database: pagila
   ```
5. Click "Test Connection" (should succeed)
6. Click "Save"

### Step 1.8: Run Metadata Ingestion

1. Go to "Services" → "Databases" → "pagila-local"
2. Click "+ Add Ingestion"
3. Select "Metadata Ingestion"
4. Configure:
   ```
   Name: pagila-metadata-ingestion
   Database Filter: pagila (include)
   Schema Filter: public (include)
   Table Filter: * (include all)
   ```
5. Schedule: "Run manually"
6. Click "Deploy"
7. Click "Run" to execute immediately

Wait 1-2 minutes for ingestion to complete.

### Step 1.9: Verify Metadata

1. Go to "Explore" → "Tables"
2. You should see pagila tables: actor, address, category, city, country, customer, film, etc.
3. Click on a table (e.g., "film")
4. Verify you can see:
   - Schema (columns, types)
   - Sample data
   - Relationships (foreign keys)

### Step 1.10: Phase 1 Validation Checklist

- [ ] OpenMetadata services start without errors
- [ ] UI accessible at localhost:8585
- [ ] Can login with default credentials
- [ ] Pagila connection created successfully
- [ ] Metadata ingestion runs successfully
- [ ] Tables visible in OpenMetadata UI
- [ ] Table schema details correct
- [ ] Foreign key relationships visible

**Phase 1 SUCCESS CRITERIA MET!**

---

## Phase 2: Kerberos Integration (SQL Server)

**Timeline:** 2-3 days
**Goal:** Enable SQL Server metadata harvesting via Kerberos sidecar

### Step 2.1: Enable Kerberos in Ingestion Container

Edit `platform-bootstrap/docker-compose.openmetadata.yml`:

Uncomment Kerberos configuration in `openmetadata-ingestion` service:

```yaml
openmetadata-ingestion:
  # ... existing configuration ...

  environment:
    # ... existing environment variables ...

    # Kerberos configuration (UNCOMMENT THESE)
    KRB5CCNAME: /krb5/cache/krb5cc
    KRB5_CONFIG: /etc/krb5.conf

  volumes:
    # Kerberos integration (UNCOMMENT THESE)
    - platform_kerberos_cache:/krb5/cache:ro
    - ${KRB5_CONF_PATH:-/etc/krb5.conf}:/etc/krb5.conf:ro

    # ... existing volumes ...

  depends_on:
    openmetadata-server:
      condition: service_healthy
    developer-kerberos-service:  # ADD THIS DEPENDENCY
      condition: service_started
```

Also add the Kerberos volume reference at the bottom:

```yaml
volumes:
  # ... existing volumes ...

  # Kerberos cache (external - managed by base compose)
  platform_kerberos_cache:
    external: true
```

### Step 2.2: Restart Services with Kerberos

```bash
cd platform-bootstrap

# Stop current stack
make openmetadata-stop

# Ensure Kerberos sidecar is running
make platform-start

# Start OpenMetadata with Kerberos
make openmetadata-start

# Verify ingestion container can see ticket
docker exec openmetadata-ingestion klist -s
```

**Expected:** No errors (klist exits with 0)

### Step 2.3: Create Kerberos Diagnostic Script

Create `platform-bootstrap/diagnostics/test-openmetadata-krb.sh`:

```bash
#!/bin/bash
# OpenMetadata Kerberos Integration Diagnostic
# Tests that ingestion container can use Kerberos tickets

set -e

# Load formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    # Fallback
    print_check() { echo "[$1] $2"; }
    print_header() { echo "=== $1 ==="; }
    GREEN='' RED='' CYAN='' NC=''
fi

print_header "OpenMetadata Kerberos Diagnostic"
echo ""

# 1. Check if OpenMetadata ingestion is running
echo "1. Checking OpenMetadata ingestion container..."
if ! docker ps --format '{{.Names}}' | grep -q "openmetadata-ingestion"; then
    print_check "FAIL" "OpenMetadata ingestion container not running"
    echo ""
    echo "Start it with: make openmetadata-start"
    exit 1
fi
print_check "PASS" "Container is running"

# 2. Check if Kerberos sidecar is running
echo ""
echo "2. Checking Kerberos sidecar..."
if ! docker ps --format '{{.Names}}' | grep -q "kerberos-platform-service"; then
    print_check "FAIL" "Kerberos sidecar not running"
    echo ""
    echo "Start it with: make platform-start"
    exit 1
fi
print_check "PASS" "Kerberos sidecar is running"

# 3. Check if ticket cache is mounted
echo ""
echo "3. Checking Kerberos volume mount..."
if docker exec openmetadata-ingestion test -f /krb5/cache/krb5cc; then
    print_check "PASS" "Ticket cache file exists in container"
else
    print_check "FAIL" "Ticket cache not found at /krb5/cache/krb5cc"
    echo ""
    echo "Check volume mount configuration"
    exit 1
fi

# 4. Check if ticket is valid
echo ""
echo "4. Checking Kerberos ticket validity..."
if docker exec openmetadata-ingestion klist -s 2>/dev/null; then
    print_check "PASS" "Valid Kerberos ticket found"
    echo ""
    echo "Ticket details:"
    docker exec openmetadata-ingestion klist 2>/dev/null | head -5 | sed 's/^/  /'
else
    print_check "FAIL" "No valid Kerberos ticket"
    echo ""
    echo "Check:"
    echo "  1. Run 'kinit' on host to get ticket"
    echo "  2. Verify sidecar logs: docker logs kerberos-platform-service"
    exit 1
fi

# 5. Check krb5.conf
echo ""
echo "5. Checking Kerberos configuration..."
if docker exec openmetadata-ingestion test -f /etc/krb5.conf; then
    print_check "PASS" "krb5.conf is mounted"
    echo ""
    echo "Default realm:"
    docker exec openmetadata-ingestion grep "default_realm" /etc/krb5.conf | sed 's/^/  /'
else
    print_check "FAIL" "krb5.conf not found"
    exit 1
fi

# 6. Test SQL Server connectivity (if provided)
SQL_SERVER="${1:-}"
if [ -n "$SQL_SERVER" ]; then
    echo ""
    echo "6. Testing SQL Server connectivity..."
    echo "   Target: $SQL_SERVER"

    if docker exec openmetadata-ingestion timeout 5 bash -c "echo > /dev/tcp/$SQL_SERVER/1433" 2>/dev/null; then
        print_check "PASS" "Can reach SQL Server on port 1433"
    else
        print_check "FAIL" "Cannot reach SQL Server"
        echo ""
        echo "Check network connectivity and VPN"
        exit 1
    fi
fi

echo ""
print_divider
print_check "PASS" "All diagnostics passed!"
print_divider
echo ""
echo "OpenMetadata ingestion container is ready for Kerberos-based SQL Server connections."
echo ""
if [ -z "$SQL_SERVER" ]; then
    echo "To test SQL Server connectivity, run:"
    echo "  $0 <sql-server-hostname>"
fi
```

Make it executable:

```bash
chmod +x platform-bootstrap/diagnostics/test-openmetadata-krb.sh
```

### Step 2.4: Run Kerberos Diagnostic

```bash
cd platform-bootstrap

# Basic test
./diagnostics/test-openmetadata-krb.sh

# Test with SQL Server
./diagnostics/test-openmetadata-krb.sh sqlserver01.company.com
```

**Expected Output:**
```
=== OpenMetadata Kerberos Diagnostic ===

1. Checking OpenMetadata ingestion container...
[PASS] Container is running

2. Checking Kerberos sidecar...
[PASS] Kerberos sidecar is running

3. Checking Kerberos volume mount...
[PASS] Ticket cache file exists in container

4. Checking Kerberos ticket validity...
[PASS] Valid Kerberos ticket found

Ticket details:
  Ticket cache: FILE:/krb5/cache/krb5cc
  Default principal: your.name@DOMAIN.COM

5. Checking Kerberos configuration...
[PASS] krb5.conf is mounted

Default realm:
  default_realm = DOMAIN.COM

========================================
[PASS] All diagnostics passed!
========================================

OpenMetadata ingestion container is ready for Kerberos-based SQL Server connections.
```

### Step 2.5: Configure SQL Server Connection

In OpenMetadata UI:

1. Go to "Settings" → "Services" → "Databases"
2. Click "+ Add Database"
3. Select "MSSQL"
4. Configure connection:
   ```
   Name: corporate-sql-server
   Connection Type: Mssql
   Host: sqlserver01.company.com
   Port: 1433
   Database: TestDB

   # Authentication (IMPORTANT!)
   Username: (leave empty)
   Password: (leave empty)

   # Connection Options (click "+ Add Option")
   Key: driver
   Value: ODBC Driver 18 for SQL Server

   Key: TrustServerCertificate
   Value: yes

   Key: Trusted_Connection
   Value: yes
   ```
5. Click "Test Connection"
6. Should see: "Connection successful!"
7. Click "Save"

### Step 2.6: Run SQL Server Metadata Ingestion

1. Go to "Services" → "Databases" → "corporate-sql-server"
2. Click "+ Add Ingestion"
3. Select "Metadata Ingestion"
4. Configure:
   ```
   Name: sqlserver-metadata-ingestion
   Database Filter: TestDB (or your database)
   Schema Filter: dbo (or specific schema)
   Table Filter: * (all tables)
   ```
5. Schedule: "Run manually"
6. Click "Deploy"
7. Click "Run"

Monitor ingestion in "Ingestion" tab.

### Step 2.7: Verify SQL Server Metadata

1. Go to "Explore" → "Tables"
2. Filter by service: "corporate-sql-server"
3. Verify SQL Server tables appear
4. Click on a table to view schema

### Step 2.8: Troubleshooting SQL Server Connection

If connection fails, check:

1. **Kerberos ticket valid?**
   ```bash
   ./diagnostics/test-openmetadata-krb.sh
   ```

2. **SQL Server reachable?**
   ```bash
   docker exec openmetadata-ingestion nc -zv sqlserver01.company.com 1433
   ```

3. **ODBC driver installed?**
   ```bash
   docker exec openmetadata-ingestion odbcinst -q -d
   # Should show: ODBC Driver 18 for SQL Server
   ```

4. **Test direct connection:**
   ```bash
   docker exec -it openmetadata-ingestion bash

   # Inside container
   sqlcmd -S sqlserver01.company.com -d TestDB -E -C -Q "SELECT @@VERSION"
   ```

5. **Check ingestion logs:**
   ```bash
   docker logs openmetadata-ingestion | grep -i error
   ```

### Step 2.9: Phase 2 Validation Checklist

- [ ] Kerberos volume mounted in ingestion container
- [ ] `klist` shows valid ticket in container
- [ ] Diagnostic script passes all tests
- [ ] SQL Server connection created without username/password
- [ ] Test connection succeeds
- [ ] Metadata ingestion runs successfully
- [ ] SQL Server tables visible in OpenMetadata
- [ ] No authentication errors in logs

**Phase 2 SUCCESS CRITERIA MET!**

---

## Phase 3: Airflow Integration (Lineage Tracking)

**Timeline:** 3-5 days
**Goal:** Enable pipeline metadata and lineage tracking from Astronomer DAGs

### Step 3.1: Configure Airflow Pipeline Service

In OpenMetadata UI:

1. Go to "Settings" → "Services" → "Pipelines"
2. Click "+ Add Pipeline"
3. Select "Airflow"
4. Configure:
   ```
   Name: astronomer-local
   Connection Type: Backend
   Host: http://host.docker.internal:8080

   # If Airflow has auth enabled
   Username: admin
   Password: admin

   # Advanced
   Connection Timeout: 60
   ```
5. Click "Test Connection"
6. Click "Save"

### Step 3.2: Create Test Datakit with Lineage

Using the examples repository:

```bash
cd ~/repos/airflow-data-platform-examples
cd pagila-implementations/pagila-sqlmodel-basic

# Start Astronomer Airflow
astro dev start
```

### Step 3.3: Add Lineage to Example DAG

Edit `dags/pagila_basic_dag.py` to add lineage:

```python
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

# Define inlets and outlets for lineage
def extract_film_data(**context):
    """Extract film data from pagila database"""
    # Your extraction logic
    pass

with DAG(
    'pagila_basic_etl',
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,
    catchup=False,
) as dag:

    extract_films = PythonOperator(
        task_id='extract_films',
        python_callable=extract_film_data,
        # Lineage: declare data sources and destinations
        inlets=[{
            'table': 'film',
            'service': 'pagila-local',
            'database': 'pagila',
            'schema': 'public'
        }],
        outlets=[{
            'table': 'dim_film',
            'service': 'warehouse',
            'database': 'analytics',
            'schema': 'public'
        }]
    )
```

Restart Airflow to load changes:

```bash
astro dev restart
```

### Step 3.4: Run Pipeline Ingestion

In OpenMetadata UI:

1. Go to "Services" → "Pipelines" → "astronomer-local"
2. Click "+ Add Ingestion"
3. Select "Metadata Ingestion"
4. Configure:
   ```
   Name: airflow-metadata-ingestion
   Pipeline Filter: pagila* (include only pagila DAGs)
   ```
5. Click "Deploy"
6. Click "Run"

Wait for ingestion to complete.

### Step 3.5: Verify Pipeline Metadata

1. Go to "Explore" → "Pipelines"
2. Find "pagila_basic_etl"
3. Click to view details
4. Verify:
   - DAG structure visible
   - Tasks listed
   - Schedule information
   - Owner (if configured)

### Step 3.6: Verify Lineage Graph

1. Go to "Explore" → "Tables"
2. Click on "film" table (pagila)
3. Click "Lineage" tab
4. Should see lineage graph:
   ```
   film (pagila) → pagila_basic_etl → dim_film (warehouse)
   ```

### Step 3.7: Install OpenMetadata Lineage Operator (Optional)

For more explicit lineage capture, install operator in Airflow:

Edit `requirements.txt` in your datakit:

```txt
# Add to requirements.txt
openmetadata-managed-apis==1.2.0
```

Then rebuild:

```bash
astro dev stop
astro dev start
```

Update DAG to use lineage operator:

```python
from openmetadata.airflow.lineage import OpenMetadataLineageOperator

with DAG('pagila_with_lineage_operator', ...) as dag:

    # Explicit lineage tracking
    track_lineage = OpenMetadataLineageOperator(
        task_id='track_lineage',
        service_name='pagila-local',
        dag_id='pagila_basic_etl',
        task_id_to_lineage={
            'extract_films': {
                'inlets': ['film'],
                'outlets': ['dim_film']
            }
        }
    )
```

### Step 3.8: Test Lineage Backend (Advanced)

For automatic lineage capture without code changes:

Edit Airflow configuration in your datakit's `docker-compose.override.yml`:

```yaml
x-airflow-common:
  &airflow-common
  environment:
    # Enable OpenMetadata lineage backend
    AIRFLOW__LINEAGE__BACKEND: openmetadata_lineage_backend.OpenMetadataLineageBackend
    OPENMETADATA_API_ENDPOINT: http://openmetadata-server:8585/api
    # Note: Requires JWT token - see OpenMetadata docs for setup
```

Restart Airflow and run DAG - lineage automatically captured!

### Step 3.9: Update Cookiecutter Template

Add lineage patterns to `cookiecutter-layer2-datakit`:

**File:** `{{cookiecutter.datakit_name}}/requirements.txt`

```txt
# OpenMetadata lineage (optional, uncomment to enable)
# openmetadata-managed-apis==1.2.0
```

**File:** `{{cookiecutter.datakit_name}}/dags/example_dag.py`

```python
# Example DAG with lineage tracking
#
# To enable lineage:
# 1. Uncomment openmetadata-managed-apis in requirements.txt
# 2. Configure inlets and outlets on operators
# 3. Lineage will appear in OpenMetadata automatically

from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

def my_task(**context):
    # Your task logic
    pass

with DAG(
    '{{cookiecutter.datakit_name}}_example',
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,
) as dag:

    task = PythonOperator(
        task_id='my_task',
        python_callable=my_task,
        # Lineage metadata (optional)
        inlets=[{
            'table': 'source_table',
            'service': 'source-database',
            'database': 'source_db'
        }],
        outlets=[{
            'table': 'target_table',
            'service': 'target-database',
            'database': 'target_db'
        }]
    )
```

### Step 3.10: Phase 3 Validation Checklist

- [ ] Airflow pipeline service configured
- [ ] Test connection to Astronomer succeeds
- [ ] Pipeline metadata ingestion runs successfully
- [ ] DAGs visible in OpenMetadata
- [ ] DAG structure and tasks shown correctly
- [ ] Lineage graph appears for tables with inlets/outlets
- [ ] Lineage operator works (if installed)
- [ ] Cookiecutter template updated with lineage patterns

**Phase 3 SUCCESS CRITERIA MET!**

---

## Phase 4: Platform Integration (Production Ready)

**Timeline:** 5-7 days
**Goal:** Make OpenMetadata a standard, documented platform service

### Step 4.1: Update Platform Architecture Documentation

Edit `docs/platform-architecture-vision.md`:

Add OpenMetadata to Layer 1.5 architecture diagram and descriptions.

### Step 4.2: Create Developer Guide

Create `docs/openmetadata-developer-guide.md`:

(See separate document - covers browsing metadata, searching tables, understanding lineage, adding lineage to DAGs)

### Step 4.3: Create Administrator Guide

Create `docs/openmetadata-admin-guide.md`:

(See separate document - covers operations, troubleshooting, backup/restore, monitoring)

### Step 4.4: Add to Platform Setup Wizard

Edit `platform-bootstrap/dev-tools/setup-kerberos.sh`:

Add optional OpenMetadata setup step after step 11:

```bash
step_12_openmetadata_setup() {
    print_step 12 "OpenMetadata Setup (Optional)"

    echo "OpenMetadata provides metadata management and data cataloging."
    echo ""
    echo "Features:"
    echo "  • Schema discovery and documentation"
    echo "  • Data lineage tracking"
    echo "  • Search across all data assets"
    echo "  • Integration with Airflow"
    echo ""

    if ! ask_yes_no "Install OpenMetadata?"; then
        print_info "Skipping OpenMetadata setup"
        save_state
        return 0
    fi

    echo ""
    print_info "Starting OpenMetadata services..."

    if make openmetadata-start; then
        echo ""
        print_success "OpenMetadata started successfully!"
        echo ""
        echo "Access OpenMetadata:"
        echo "  URL: http://localhost:8585"
        echo "  Email: admin@open-metadata.org"
        echo "  Password: admin"
        echo ""
        echo "Next steps:"
        echo "  1. Login to OpenMetadata UI"
        echo "  2. Configure data source connections"
        echo "  3. Run metadata ingestion"
        echo ""
        echo "See docs/openmetadata-developer-guide.md for usage"
    else
        print_error "Failed to start OpenMetadata"
        echo ""
        echo "Check logs: make openmetadata-logs"
    fi

    save_state
}
```

Update main execution to include step 12:

```bash
# In main() function
[ $CURRENT_STEP -le 12 ] && { step_12_openmetadata_setup && CURRENT_STEP=13; }
```

### Step 4.5: Configure for Corporate Environment

Create `platform-bootstrap/docs/openmetadata-corporate-setup.md`:

Document Artifactory configuration, image paths, network restrictions.

### Step 4.6: Add Health Checks

Create `platform-bootstrap/scripts/health-check-openmetadata.sh`:

```bash
#!/bin/bash
# OpenMetadata health check script
# Used for monitoring and alerting

set -e

# Check if services are running
check_service_running() {
    local service_name=$1
    if docker ps --format '{{.Names}}' | grep -q "$service_name"; then
        return 0
    else
        return 1
    fi
}

# Check HTTP endpoint
check_http_endpoint() {
    local url=$1
    local name=$2
    if curl -sf "$url" >/dev/null 2>&1; then
        echo "✓ $name is healthy"
        return 0
    else
        echo "✗ $name is unhealthy"
        return 1
    fi
}

# Main health check
all_healthy=true

# Check containers
if ! check_service_running "openmetadata-server"; then
    echo "✗ OpenMetadata server not running"
    all_healthy=false
fi

if ! check_service_running "openmetadata-ingestion"; then
    echo "✗ OpenMetadata ingestion not running"
    all_healthy=false
fi

# Check endpoints
if ! check_http_endpoint "http://localhost:8585/api/v1/health" "OpenMetadata Server"; then
    all_healthy=false
fi

if ! check_http_endpoint "http://localhost:8080/health" "Ingestion Airflow"; then
    all_healthy=false
fi

if [ "$all_healthy" = true ]; then
    echo ""
    echo "All OpenMetadata services are healthy"
    exit 0
else
    echo ""
    echo "Some OpenMetadata services are unhealthy"
    exit 1
fi
```

### Step 4.7: Create Backup and Restore Scripts

Create `platform-bootstrap/scripts/backup-openmetadata.sh`:

```bash
#!/bin/bash
# Backup OpenMetadata metadata database

set -e

BACKUP_DIR="${1:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/openmetadata_backup_$TIMESTAMP.sql"

mkdir -p "$BACKUP_DIR"

echo "Backing up OpenMetadata database..."
docker exec openmetadata-postgres pg_dump -U openmetadata_user openmetadata_db > "$BACKUP_FILE"

echo "Backup saved to: $BACKUP_FILE"
echo "Size: $(du -h "$BACKUP_FILE" | cut -f1)"
```

Create `platform-bootstrap/scripts/restore-openmetadata.sh`:

```bash
#!/bin/bash
# Restore OpenMetadata from backup

set -e

BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup-file.sql>"
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "WARNING: This will overwrite current OpenMetadata data!"
read -p "Continue? [y/N] " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo "Restoring OpenMetadata database..."
docker exec -i openmetadata-postgres psql -U openmetadata_user openmetadata_db < "$BACKUP_FILE"

echo "Restore complete!"
```

Make scripts executable:

```bash
chmod +x platform-bootstrap/scripts/backup-openmetadata.sh
chmod +x platform-bootstrap/scripts/restore-openmetadata.sh
chmod +x platform-bootstrap/scripts/health-check-openmetadata.sh
```

### Step 4.8: Add Monitoring to Makefile

Add to `Makefile`:

```makefile
.PHONY: openmetadata-health
openmetadata-health: ## Check OpenMetadata health
	@./scripts/health-check-openmetadata.sh

.PHONY: openmetadata-backup
openmetadata-backup: ## Backup OpenMetadata metadata
	@./scripts/backup-openmetadata.sh

.PHONY: openmetadata-restore
openmetadata-restore: ## Restore OpenMetadata from backup (requires: BACKUP=file.sql)
	@if [ -z "$(BACKUP)" ]; then \
		echo "Error: BACKUP file not specified"; \
		echo "Usage: make openmetadata-restore BACKUP=backups/openmetadata_backup_20250116_120000.sql"; \
		exit 1; \
	fi
	@./scripts/restore-openmetadata.sh "$(BACKUP)"
```

### Step 4.9: Phase 4 Validation Checklist

- [ ] Platform architecture documentation updated
- [ ] Developer guide created and tested
- [ ] Administrator guide created
- [ ] Setup wizard includes OpenMetadata option
- [ ] Corporate environment configuration documented
- [ ] Health check script works
- [ ] Backup/restore scripts tested
- [ ] Monitoring integrated

**Phase 4 SUCCESS CRITERIA MET!**

---

## Post-Implementation Tasks

### Documentation Updates

- [ ] Update main README.md with OpenMetadata info
- [ ] Add screenshots to developer guide
- [ ] Create troubleshooting FAQ
- [ ] Document known issues and workarounds

### Team Rollout

- [ ] Demo OpenMetadata to team
- [ ] Provide training on metadata management
- [ ] Share examples of good lineage patterns
- [ ] Establish metadata governance guidelines

### Continuous Improvement

- [ ] Collect user feedback
- [ ] Monitor resource usage
- [ ] Track adoption metrics
- [ ] Plan future enhancements

---

## Troubleshooting Guide

### Issue: Services fail to start

**Symptoms:** `docker compose up` fails or services crash

**Solutions:**
1. Check Docker resource allocation (need 8GB RAM)
2. Check port conflicts: `netstat -an | grep 8585`
3. Review logs: `make openmetadata-logs`
4. Try clean start: `make openmetadata-clean && make openmetadata-start`

### Issue: Can't access UI

**Symptoms:** http://localhost:8585 doesn't load

**Solutions:**
1. Check if server is healthy: `curl http://localhost:8585/api/v1/health`
2. Wait longer (first start takes 2-3 minutes)
3. Check firewall: `sudo ufw status`
4. Try different browser or incognito mode

### Issue: Kerberos authentication fails

**Symptoms:** SQL Server connection fails with "Cannot authenticate"

**Solutions:**
1. Run diagnostic: `./diagnostics/test-openmetadata-krb.sh`
2. Verify ticket: `docker exec openmetadata-ingestion klist`
3. Check volume mount: `docker exec openmetadata-ingestion ls -la /krb5/cache/`
4. Restart sidecar: `make platform-restart`

### Issue: Metadata ingestion fails

**Symptoms:** Ingestion shows "Failed" status

**Solutions:**
1. Check ingestion logs in UI (Ingestion → View Logs)
2. Test connection manually (Services → Test Connection)
3. Verify database is reachable from container
4. Check credentials or Kerberos ticket validity

### Issue: Lineage not appearing

**Symptoms:** Tables show no lineage graph

**Solutions:**
1. Verify inlets/outlets are configured in DAG
2. Run DAG at least once (lineage captured on execution)
3. Check Airflow pipeline service connection
4. Verify table/service names match exactly

---

## Appendix: Complete File Listing

After full implementation, you should have:

```
platform-bootstrap/
├── docker-compose.yml (existing)
├── docker-compose.openmetadata.yml (NEW)
├── .env (updated)
├── .env.example (updated)
├── Makefile (updated)
├── openmetadata/
│   └── dags/
│       └── .gitkeep
├── diagnostics/
│   ├── test-openmetadata-krb.sh (NEW)
│   └── ... (existing)
└── scripts/
    ├── backup-openmetadata.sh (NEW)
    ├── restore-openmetadata.sh (NEW)
    └── health-check-openmetadata.sh (NEW)

docs/
├── openmetadata-integration-design.md (NEW)
├── openmetadata-implementation-spec.md (THIS FILE)
├── openmetadata-developer-guide.md (Phase 4)
├── openmetadata-admin-guide.md (Phase 4)
└── openmetadata-corporate-setup.md (Phase 4)
```

---

## Next Steps

1. Begin Phase 1 implementation
2. Validate each phase before proceeding
3. Create additional documentation as needed
4. Gather feedback and iterate

**Ready to implement!**
