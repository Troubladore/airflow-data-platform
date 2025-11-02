# OpenMetadata Integration Design

**Status:** Design Document
**Date:** 2025-01-16
**Purpose:** Define the architecture and implementation approach for integrating OpenMetadata with the Airflow Data Platform as a Layer 1.5 metadata management service.

---

## Executive Summary

OpenMetadata will be integrated as a **Layer 1.5 platform service** that provides schema discovery, data cataloging, and lineage tracking capabilities. The integration leverages the existing Kerberos sidecar pattern to enable SQL Server authentication, while also supporting PostgreSQL and deep Airflow integration for pipeline metadata and lineage tracking.

**Key Insight:** OpenMetadata has native, deep integration with Airflow that makes it a natural complement to Astronomer-based platforms rather than a competing tool.

---

## Business Value

### Short-Term (Immediate Benefits)
- **Schema Discovery**: Automated harvesting of pagila (PostgreSQL) schema to accelerate examples repository development
- **Documentation Generation**: Auto-generated data dictionaries and schema documentation
- **Pattern Validation**: Proves Kerberos sidecar works with additional use cases beyond direct SQL connections

### Medium-Term (3-6 months)
- **SQL Server Metadata**: Corporate database schema discovery using Kerberos authentication
- **Search & Discovery**: Searchable catalog of all data assets across environments
- **Developer Productivity**: Reduced time finding tables, understanding schemas, identifying relationships

### Long-Term (Strategic)
- **Automated Lineage**: Data flow tracking through Airflow DAGs without manual documentation
- **Impact Analysis**: Understand downstream effects before making changes
- **Data Governance**: Foundation for enterprise data governance and compliance
- **Team Collaboration**: Shared knowledge base for data assets and transformations

---

## Architecture Overview

### Layer 1.5: Platform Services

OpenMetadata sits between Layer 1 (base image) and Layer 2 (datakits) as a **standard platform service**:

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 1: Base Image (Astronomer + sqlmodel-framework)          │
│ - Kerberos client libraries                                    │
│ - SQL Server ODBC drivers                                      │
│ - Common Python dependencies                                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Layer 1.5: Platform Services (platform-bootstrap)              │
│                                                                 │
│ ┌───────────────────┐  ┌──────────────────────────────────┐    │
│ │ Kerberos Sidecar  │  │ Shared Platform PostgreSQL       │    │
│ │                   │  │ ├── openmetadata_db              │    │
│ │ Shares tickets    │  │ ├── airflow_metastore_db (future)│    │
│ │ via volume        │  │ └── [other platform apps]        │    │
│ └───────────────────┘  └──────────────────────────────────┘    │
│                                                                 │
│ ┌──────────────────────────────────────────────────────────┐   │
│ │ OpenMetadata Stack (3 services)                         │   │
│ │ ├── Server (UI + API + built-in connectors)            │   │
│ │ ├── Uses shared PostgreSQL (OLTP workloads)            │   │
│ │ └── Elasticsearch (search indexing)                    │   │
│ └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│ Shared: platform_kerberos_cache volume                         │
│ Shared: platform_network                                       │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Layer 2: Datakits (Astronomer Airflow Projects)                │
│ - Run ingestion DAGs (everything as code!)                     │
│ - Mount platform_kerberos_cache for SQL Server access          │
│ - Connect to OpenMetadata API for metadata operations          │
│ - Emit lineage metadata from DAG executions                    │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Warehouse PostgreSQL (Separate Instance - OLAP)                │
│ - SEPARATE from platform PostgreSQL (OLTP/OLAP separation!)    │
│ - Receives transformed data from Airflow DAGs                  │
│ - Optimized for analytical queries                             │
│ - Can also be cataloged by OpenMetadata                        │
└─────────────────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Always-On Service**: OpenMetadata runs as standard platform service (like Kerberos sidecar)
2. **Shared Infrastructure**: PostgreSQL shared across platform services (matches production pattern)
3. **OLTP/OLAP Separation**: Platform PostgreSQL (OLTP) separate from warehouse PostgreSQL (OLAP)
4. **Everything as Code**: Ingestion via Astronomer DAGs (no manual UI clicking)
5. **No Redundant Services**: No separate Airflow for ingestion (uses Astronomer)
6. **Reuse Existing Patterns**: Leverages Kerberos sidecar, volume sharing, network architecture
7. **Corporate Environment Ready**: Supports Artifactory mirrors and restricted networks
8. **Astronomer-Native**: Ingestion runs in Astronomer (the platform's orchestrator)

---

## Component Architecture

### 1. Shared Platform PostgreSQL
**Purpose:** Centralized database for platform services (OLTP workloads)

**Container:** `platform-postgres`
**Image:** `postgres:15`

**Key Features:**
- **Shared across platform services** (OpenMetadata, future Airflow metastore, etc.)
- Multiple databases in single instance (production pattern!)
- Init script creates databases on first startup
- Single backup/restore process

**Databases:**
```sql
-- OpenMetadata metadata storage
CREATE DATABASE openmetadata_db OWNER openmetadata_user;

-- Future: Airflow metastore (when not using Astronomer's)
-- CREATE DATABASE airflow_db OWNER airflow_user;

-- Future: Other platform services as needed
```

**Configuration:**
```yaml
environment:
  POSTGRES_USER: platform_admin
  POSTGRES_PASSWORD: ${PLATFORM_DB_PASSWORD}
volumes:
  - platform_postgres_data:/var/lib/postgresql/data
  - ./postgres/init-databases.sh:/docker-entrypoint-initdb.d/init-databases.sh:ro
```

**Note:** This is **SEPARATE** from warehouse PostgreSQL (OLAP workloads)!

### 2. OpenMetadata Server
**Purpose:** Core metadata server with UI, API, and built-in connectors

**Container:** `openmetadata-server`
**Image:** `docker.getcollate.io/openmetadata/server:1.2.0`
**Exposed Port:** `8585` (Web UI)

**Key Features:**
- Web-based UI for browsing metadata
- REST API for programmatic access
- **Built-in connectors** for 50+ data sources (no separate ingestion container!)
- Can run connectors directly when "Test Connection" or manual ingestion triggered
- User authentication and authorization

**Dependencies:**
- Shared Platform PostgreSQL (openmetadata_db)
- Elasticsearch (search indexing)
- Kerberos sidecar (for SQL Server connections)

**Kerberos Integration:**
```yaml
environment:
  KRB5CCNAME: /krb5/cache/krb5cc
  KRB5_CONFIG: /etc/krb5.conf
volumes:
  - platform_kerberos_cache:/krb5/cache:ro
  - /etc/krb5.conf:/etc/krb5.conf:ro
```

Server can run connectors directly, using Kerberos ticket for SQL Server!

### 3. Elasticsearch
**Purpose:** Search indexing for metadata

**Container:** `openmetadata-elasticsearch`
**Image:** `docker.elastic.co/elasticsearch/elasticsearch:8.10.2`

**Configuration:**
- Single-node mode (suitable for local development)
- Security disabled (local development only)
- Persistent volume for index storage

**Resource Allocation:**
```yaml
environment:
  ES_JAVA_OPTS: -Xms1g -Xmx1g
```

### 4. ~~OpenMetadata Ingestion~~ (REMOVED!)

**Decision:** No separate ingestion container!

**Why removed:**
- Eliminates redundant Airflow instance
- Ingestion runs in **Astronomer Airflow** (everything as code!)
- Server has built-in connectors for ad-hoc use
- Saves ~2GB RAM
- Matches "everything as code" culture

**Ingestion approaches:**
1. **Programmatic** (recommended): Astronomer DAGs with OpenMetadata Python SDK
2. **Ad-hoc**: Server's built-in connectors via API or UI (quick testing)
3. **Scheduled**: Astronomer DAGs on schedule (production pattern)

---

## Database Architecture: OLTP vs OLAP Separation

**Critical Design Decision:** Platform services use **separate PostgreSQL instances** from data warehouses.

### Platform PostgreSQL (OLTP - Transactional)

**Purpose:** Platform operational data
**Container:** `platform-postgres` (in platform-bootstrap)
**Workload Type:** OLTP (Online Transaction Processing)

**Contains:**
- `openmetadata_db` - OpenMetadata metadata storage
- `airflow_db` (future) - Airflow metastore (if not using Astronomer's)
- Other platform service databases

**Characteristics:**
- Many small, fast transactions
- ACID compliance critical
- Normalized schema
- Low latency requirements
- Modest storage needs

**Access Pattern:**
- Platform services read/write constantly
- Ingestion DAGs read metadata
- No analytical queries

### Warehouse PostgreSQL (OLAP - Analytical)

**Purpose:** Data warehouse for analytics
**Container:** Separate instance (e.g., `warehouse-postgres` in datakit)
**Workload Type:** OLAP (Online Analytical Processing)

**Contains:**
- Transformed business data from source systems
- Dimensional models (star schemas)
- Aggregated tables for reporting
- Historical snapshots

**Characteristics:**
- Large batch inserts (ETL loads)
- Complex analytical queries
- Denormalized for query performance
- Higher latency acceptable
- Large storage requirements

**Access Pattern:**
- Airflow DAGs write transformed data
- BI tools query for analysis
- OpenMetadata catalogs the schema

### Why Separate?

**Performance Isolation:**
- Heavy analytical queries don't impact platform operations
- ETL loads don't slow down metadata lookups
- Independent scaling based on workload

**Resource Management:**
- OLTP: Optimize for connections and IOPS
- OLAP: Optimize for memory and CPU (complex queries)

**Backup/Recovery:**
- OLTP: Frequent backups, quick recovery (platform availability)
- OLAP: Less frequent backups, batch loads can replay

**Security:**
- OLTP: Platform services only
- OLAP: BI tools, analysts, reporting

### Example Data Flow

```
Source Systems (pagila, SQL Server)
         ↓
   Astronomer DAG (extracts data)
         ↓
   Transform (SQLModel patterns)
         ↓
Warehouse PostgreSQL (loads transformed data)
         ↓
   BI Tools (query for analysis)


Meanwhile, in parallel:

OpenMetadata Ingestion DAG
         ↓
   Catalogs source system schemas
         ↓
Platform PostgreSQL (stores metadata)
         ↓
   OpenMetadata UI (browse catalog)
```

**Key insight:** Same Astronomer DAG can:
1. Extract/transform/load data to warehouse (OLAP)
2. Update metadata catalog via OpenMetadata API (OLTP)

But these write to **different PostgreSQL instances**.

---

## Data Source Integration

### Supported Data Sources

OpenMetadata will initially support three types of data sources that align with platform goals:

#### 1. PostgreSQL (Pagila)
**Use Case:** Schema discovery for examples development
**Authentication:** Username/password (simple)
**Priority:** **Phase 1** - Proof of concept

**Configuration:**
```yaml
type: Postgres
hostPort: postgres-host:5432
username: postgres_user
password: ${POSTGRES_PASSWORD}  # From environment
database: pagila
```

**Value:**
- Demonstrate basic metadata harvesting
- No authentication complexity
- Immediate value for examples repo development

#### 2. SQL Server (Corporate Databases)
**Use Case:** Corporate data discovery
**Authentication:** Kerberos (via sidecar)
**Priority:** **Phase 2** - Kerberos validation

**Configuration:**
```yaml
type: Mssql
scheme: mssql+pyodbc
hostPort: sqlserver01.company.com:1433
database: TestDB
connectionOptions:
  driver: ODBC Driver 18 for SQL Server
  TrustServerCertificate: yes
  Trusted_Connection: yes  # Uses Kerberos ticket
```

**Value:**
- Proves Kerberos sidecar pattern works
- Enables corporate database discovery
- No credentials in configuration files

#### 3. Airflow (Pipeline Metadata)
**Use Case:** DAG lineage tracking
**Authentication:** Service-to-service
**Priority:** **Phase 3** - Strategic integration

**Configuration:**
```yaml
type: Airflow
hostPort: http://localhost:8080
# Lineage captured via:
# - Backend integration (runtime)
# - Lineage operators (explicit)
```

**Value:**
- Automated data lineage
- Impact analysis
- Pipeline documentation

---

## Kerberos Integration Pattern

### Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ Host System (Developer Workstation)                         │
│                                                              │
│ 1. kinit user@DOMAIN.COM                                    │
│    ↓                                                         │
│ 2. Ticket: /tmp/krb5cc_1000                                 │
└────────────────────┬─────────────────────────────────────────┘
                     │
                     ↓ (every 5 minutes)
┌──────────────────────────────────────────────────────────────┐
│ Docker: platform_network                                    │
│                                                              │
│ ┌────────────────────────────────────────────────────────┐  │
│ │ developer-kerberos-service                             │  │
│ │ - Copies ticket to: /krb5/cache/krb5cc                 │  │
│ │ - Volume: platform_kerberos_cache                      │  │
│ └────────────────────────────────────────────────────────┘  │
│                     │                                        │
│                     ↓ (shared volume, read-only)            │
│ ┌────────────────────────────────────────────────────────┐  │
│ │ openmetadata-ingestion                                 │  │
│ │ Environment:                                           │  │
│ │   KRB5CCNAME=/krb5/cache/krb5cc                        │  │
│ │ Volumes:                                               │  │
│ │   - platform_kerberos_cache:/krb5/cache:ro             │  │
│ │   - /etc/krb5.conf:/etc/krb5.conf:ro                   │  │
│ │                                                        │  │
│ │ → Connects to SQL Server using ticket                  │  │
│ └────────────────────────────────────────────────────────┘  │
│                                                              │
│ ┌────────────────────────────────────────────────────────┐  │
│ │ SQL Server (sqlserver01.company.com:1433)              │  │
│ │ - Validates Kerberos ticket                            │  │
│ │ - Grants access based on AD user                       │  │
│ └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### Key Components

1. **Ticket Source**: Host system's existing Kerberos ticket
2. **Ticket Sharer**: Existing `developer-kerberos-service` (no changes needed!)
3. **Shared Volume**: `platform_kerberos_cache` (already exists)
4. **Consumer**: `openmetadata-ingestion` container mounts volume read-only
5. **Corporate Config**: `/etc/krb5.conf` mounted from host

### SQL Server Connection Flow

```python
# Inside openmetadata-ingestion container

# 1. Environment variable set by Docker Compose
os.environ['KRB5CCNAME'] = '/krb5/cache/krb5cc'

# 2. pyodbc connection string
connection_string = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=sqlserver01.company.com;"
    "DATABASE=TestDB;"
    "Trusted_Connection=yes;"  # Uses Kerberos!
    "TrustServerCertificate=yes;"
)

# 3. Connection succeeds using Kerberos ticket
conn = pyodbc.connect(connection_string)

# 4. OpenMetadata harvests metadata
metadata = extract_tables_and_columns(conn)
```

### Diagnostic Integration

New diagnostic script: `platform-bootstrap/diagnostics/test-openmetadata-krb.sh`

```bash
#!/bin/bash
# Tests OpenMetadata ingestion container's Kerberos access

# 1. Check if ingestion container is running
# 2. Verify it can see Kerberos ticket
# 3. Test SQL Server connectivity
# 4. Verify metadata harvesting works
```

Follows same pattern as existing `test-sql-direct.sh` and `test-sql-container.sh`.

---

## Airflow Integration Patterns

OpenMetadata has **three complementary approaches** for Airflow integration:

### 1. Lineage Backend (Automatic)

**How it works:**
- Replaces Airflow's default lineage backend
- Automatically captures lineage from `inlets` and `outlets` in tasks
- Sends pipeline structure and execution metadata to OpenMetadata

**Configuration:**
```python
# airflow.cfg
[lineage]
backend = openmetadata_lineage_backend.OpenMetadataLineageBackend

# environment variables
OPENMETADATA_API_ENDPOINT = http://openmetadata-server:8585/api
OPENMETADATA_JWT_TOKEN = ${OM_JWT_TOKEN}
```

**Value:**
- Zero code changes in DAGs
- Works with existing Airflow patterns
- Captures execution history automatically

### 2. Lineage Operator (Explicit)

**How it works:**
- Add `OpenMetadataLineageOperator` to DAGs
- Explicitly declare data sources and sinks
- Fine-grained control over lineage capture

**Example:**
```python
from openmetadata.airflow.lineage import OpenMetadataLineageOperator

with DAG('customer_etl', ...) as dag:
    extract_customers = PythonOperator(
        task_id='extract_customers',
        python_callable=extract_from_sql,
        inlets=[{
            'table': 'customers',
            'service': 'corporate-sql-server',
            'database': 'CRM'
        }],
        outlets=[{
            'table': 'staging_customers',
            'service': 'warehouse',
            'database': 'staging'
        }]
    )

    # Lineage automatically sent to OpenMetadata
```

**Value:**
- Explicit documentation in code
- More control than backend approach
- Can capture complex transformations

### 3. Pipeline Connector (Metadata)

**How it works:**
- OpenMetadata connects to Airflow's metadata database
- Extracts DAG structure, schedules, owners
- Does not require code changes

**Configuration:**
```yaml
# In OpenMetadata UI: Create Airflow service
type: Airflow
hostPort: http://astronomer-webserver:8080
connection:
  type: Backend  # Or REST API
  backendConnection:
    username: airflow_user
    password: ${AIRFLOW_PASSWORD}
```

**Value:**
- Captures DAG metadata even without lineage
- Shows pipeline ownership and schedules
- Works with legacy DAGs

### Recommended Approach

**Phase 3 Implementation:**
1. Start with Pipeline Connector (easiest, no code changes)
2. Add Lineage Backend for automatic lineage capture
3. Update cookiecutter template to include Lineage Operator pattern
4. Document best practices for Layer 2 datakits

---

## Docker Compose Configuration

### File Location
`platform-bootstrap/docker-compose.openmetadata.yml`

This is a **separate compose file** that extends the base `docker-compose.yml`:

```bash
# Start just Kerberos (minimal)
docker compose up -d

# Start with OpenMetadata (full stack)
docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml up -d
```

### Configuration Structure

```yaml
services:
  # ============================================
  # OpenMetadata Core Services
  # ============================================

  openmetadata-postgres:
    image: ${IMAGE_POSTGRES:-postgres:15}
    container_name: openmetadata-postgres
    environment:
      POSTGRES_USER: openmetadata_user
      POSTGRES_PASSWORD: ${OPENMETADATA_DB_PASSWORD}
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

  openmetadata-elasticsearch:
    image: ${IMAGE_ELASTICSEARCH:-docker.elastic.co/elasticsearch/elasticsearch:8.10.2}
    container_name: openmetadata-elasticsearch
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

  openmetadata-server:
    image: ${IMAGE_OPENMETADATA_SERVER:-docker.getcollate.io/openmetadata/server:latest}
    container_name: openmetadata-server
    ports:
      - "${OPENMETADATA_PORT:-8585}:8585"
    environment:
      # Database configuration
      DB_DRIVER_CLASS: org.postgresql.Driver
      DB_URL: jdbc:postgresql://openmetadata-postgres:5432/openmetadata_db
      DB_USER: openmetadata_user
      DB_PASSWORD: ${OPENMETADATA_DB_PASSWORD}

      # Elasticsearch configuration
      ELASTICSEARCH_HOST: openmetadata-elasticsearch
      ELASTICSEARCH_PORT: 9200

      # OpenMetadata configuration
      OPENMETADATA_CLUSTER_NAME: ${OPENMETADATA_CLUSTER_NAME:-local-dev}

      # Authentication (basic for local development)
      AUTHENTICATION_PROVIDER: basic
      AUTHENTICATION_PUBLIC_KEYS: []

      # Pipeline service client
      PIPELINE_SERVICE_CLIENT_ENABLED: true
      PIPELINE_SERVICE_CLIENT_CLASS_NAME: org.openmetadata.service.clients.pipeline.airflow.AirflowRESTClient
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

  openmetadata-ingestion:
    image: ${IMAGE_OPENMETADATA_INGESTION:-docker.getcollate.io/openmetadata/ingestion:latest}
    container_name: openmetadata-ingestion
    environment:
      # Airflow configuration
      AIRFLOW__API__AUTH_BACKENDS: airflow.api.auth.backend.basic_auth
      AIRFLOW__CORE__EXECUTOR: LocalExecutor
      AIRFLOW__CORE__LOAD_EXAMPLES: false

      # OpenMetadata configuration
      OPENMETADATA_SERVER_URL: http://openmetadata-server:8585/api
      OPENMETADATA_CLUSTER_NAME: ${OPENMETADATA_CLUSTER_NAME:-local-dev}

      # Kerberos configuration (CRITICAL!)
      KRB5CCNAME: /krb5/cache/krb5cc
      KRB5_CONFIG: /etc/krb5.conf
    volumes:
      # Kerberos integration
      - platform_kerberos_cache:/krb5/cache:ro
      - ${KRB5_CONF_PATH:-/etc/krb5.conf}:/etc/krb5.conf:ro

      # Ingestion DAGs (optional customization)
      - ./openmetadata/dags:/opt/airflow/dags:ro
    depends_on:
      openmetadata-server:
        condition: service_healthy
      developer-kerberos-service:
        condition: service_started
    networks:
      - platform-net
    ports:
      - "${OPENMETADATA_INGESTION_PORT:-8080}:8080"

volumes:
  openmetadata_postgres_data:
    name: openmetadata_postgres_data
  openmetadata_es_data:
    name: openmetadata_es_data

# Use existing network and volume
networks:
  platform-net:
    external: true
    name: platform_network

# Kerberos volume must already exist
volumes:
  platform_kerberos_cache:
    external: true
```

### Configuration Management

OpenMetadata configuration is managed through the platform setup wizard (`./platform setup`), which generates `platform-config.yaml` with the following OpenMetadata settings:

```yaml
# ============================================
# OpenMetadata Configuration
# ============================================

openmetadata:
  # Server
  port: 8585
  cluster_name: local-dev

  # Images (override for corporate Artifactory)
  images:
    server: docker.getcollate.io/openmetadata/server:1.2.0
    ingestion: docker.getcollate.io/openmetadata/ingestion:1.2.0
    elasticsearch: docker.elastic.co/elasticsearch/elasticsearch:8.10.2
    postgres: postgres:15

  # Database (generated during setup)
  db_password: <auto-generated-secure-password>

  # Ingestion Airflow
  ingestion_port: 8080
```

---

## Makefile Integration

Add to `platform-bootstrap/Makefile`:

```makefile
# ============================================
# OpenMetadata Management
# ============================================

.PHONY: openmetadata-start
openmetadata-start: ## Start OpenMetadata services (includes Kerberos)
	@echo "Starting OpenMetadata stack..."
	@docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml up -d
	@echo ""
	@echo "OpenMetadata is starting..."
	@echo "  UI:        http://localhost:8585"
	@echo "  Ingestion: http://localhost:8080"
	@echo ""
	@echo "Default credentials:"
	@echo "  Username: admin"
	@echo "  Email:    admin@open-metadata.org"
	@echo "  Password: admin"

.PHONY: openmetadata-stop
openmetadata-stop: ## Stop OpenMetadata services
	@echo "Stopping OpenMetadata stack..."
	@docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml down

.PHONY: openmetadata-status
openmetadata-status: ## Check OpenMetadata services status
	@echo "OpenMetadata Services Status:"
	@echo "=============================="
	@docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml ps
	@echo ""
	@echo "Health checks:"
	@echo "  OpenMetadata Server: $$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8585/api/v1/health 2>/dev/null || echo "DOWN")"
	@echo "  Ingestion Airflow:   $$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health 2>/dev/null || echo "DOWN")"

.PHONY: openmetadata-logs
openmetadata-logs: ## Show OpenMetadata logs
	@docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml logs -f

.PHONY: openmetadata-clean
openmetadata-clean: ## Remove OpenMetadata data (WARNING: deletes all metadata)
	@echo "WARNING: This will delete ALL OpenMetadata data!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker compose -f docker-compose.yml -f docker-compose.openmetadata.yml down -v; \
		echo "OpenMetadata data deleted."; \
	else \
		echo "Cancelled."; \
	fi
```

Update main help target:

```makefile
.PHONY: help
help: ## Show this help message
	@echo "Platform Bootstrap - Service Management"
	@echo ""
	@echo "Core Services:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -v "openmetadata" | awk '...'
	@echo ""
	@echo "OpenMetadata (Optional):"
	@grep -E '^openmetadata-[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk '...'
```

---

## Implementation Phases

### Phase 1: Proof of Concept (1-2 days)

**Goal:** Demonstrate OpenMetadata can harvest pagila schema

**Tasks:**
1. Create `docker-compose.openmetadata.yml`
2. Add OpenMetadata targets to Makefile
3. Integrate OpenMetadata in setup wizard (`./platform setup`)
4. Start services and verify UI accessibility
5. Configure pagila PostgreSQL connection
6. Harvest metadata and verify in UI

**Deliverables:**
- [ ] Docker Compose configuration file
- [ ] Setup wizard integration for OpenMetadata
- [ ] Makefile targets working
- [ ] OpenMetadata UI accessible at localhost:8585
- [ ] Pagila metadata visible in OpenMetadata
- [ ] Screenshots for documentation

**Success Criteria:**
- Services start without errors
- UI loads and is navigable
- Pagila connection successful
- Table metadata visible (columns, types, relationships)

### Phase 2: Kerberos Integration (2-3 days)

**Goal:** Enable SQL Server metadata harvesting via Kerberos

**Tasks:**
1. Verify ingestion container has access to ticket
2. Create diagnostic script: `test-openmetadata-krb.sh`
3. Configure SQL Server connection with Kerberos
4. Test metadata harvesting from corporate database
5. Document connection configuration pattern
6. Create troubleshooting guide

**Deliverables:**
- [ ] Diagnostic script for Kerberos validation
- [ ] SQL Server connection configuration guide
- [ ] Kerberos troubleshooting documentation
- [ ] Corporate SQL Server metadata harvested successfully

**Success Criteria:**
- `klist` shows valid ticket inside ingestion container
- SQL Server connection succeeds without username/password
- Metadata harvested from at least one corporate database
- Diagnostic script helps debug issues

### Phase 3: Airflow Integration (3-5 days)

**Goal:** Enable pipeline metadata and lineage tracking

**Tasks:**
1. Configure Pipeline Connector to Astronomer
2. Install lineage backend in test datakit
3. Add OpenMetadataLineageOperator example to DAG
4. Verify lineage capture from inlets/outlets
5. Update cookiecutter template with lineage patterns
6. Document best practices for Layer 2 datakits

**Deliverables:**
- [ ] Airflow pipeline metadata visible in OpenMetadata
- [ ] Lineage graph showing table → DAG → table relationships
- [ ] Cookiecutter template includes lineage operators
- [ ] Developer guide for adding lineage to DAGs

**Success Criteria:**
- DAG structure appears in OpenMetadata
- Task execution history tracked
- Lineage graph correctly shows data flow
- New datakits from cookiecutter include lineage by default

### Phase 4: Platform Integration (5-7 days)

**Goal:** Make OpenMetadata a standard (optional) platform service

**Tasks:**
1. Update platform architecture documentation
2. Create "Getting Started with OpenMetadata" guide
3. Add OpenMetadata to setup wizard (optional step)
4. Configure for corporate environment (Artifactory images)
5. Add monitoring and health checks
6. Create backup/restore procedures

**Deliverables:**
- [ ] Updated platform-architecture-vision.md
- [ ] OpenMetadata getting started guide
- [ ] Corporate environment configuration documented
- [ ] Backup/restore scripts
- [ ] Health check integration

**Success Criteria:**
- Documentation complete and accurate
- Setup wizard includes OpenMetadata option
- Corporate Artifactory images configurable
- Health checks integrated with platform monitoring

---

## Corporate Environment Configuration

### Artifactory Image Paths

Configure corporate Artifactory paths through the setup wizard (`./platform setup`), which will update `platform-config.yaml`:

```yaml
# Corporate Artifactory paths
openmetadata:
  images:
    server: artifactory.company.com/docker-remote/openmetadata/server:1.2.0
    ingestion: artifactory.company.com/docker-remote/openmetadata/ingestion:1.2.0
    elasticsearch: artifactory.company.com/docker-remote/elasticsearch/elasticsearch:8.10.2
    postgres: artifactory.company.com/docker-remote/library/postgres:15
```

### Docker Login Requirement

Before starting OpenMetadata in corporate environment:

```bash
docker login artifactory.company.com
# Username: your_username
# Password: your_token
```

This follows the same pattern as existing Astronomer images.

### Network Restrictions

If corporate network blocks OpenMetadata's default image registry:

1. Work with IT to mirror images to Artifactory
2. Update `.env` with Artifactory paths
3. Document specific corporate paths in team wiki

---

## Security Considerations

### 1. Credential Management

**NEVER store credentials in configuration files:**

✅ **Correct:**
- Kerberos tickets via sidecar (no passwords)
- Environment variables from `.env` (not in git)
- Docker secrets for sensitive values
- Vault integration (future consideration)

❌ **Incorrect:**
- Hardcoded passwords in YAML
- SQL connection strings with credentials
- API tokens in docker-compose files

### 2. Network Isolation

**Local development (relaxed):**
- All services on `platform-net`
- OpenMetadata UI exposed to host (port 8585)
- Ingestion Airflow exposed to host (port 8080)

**Production (restricted):**
- OpenMetadata on internal network only
- Reverse proxy with authentication
- No direct database access from ingestion

### 3. Access Control

**Phase 1-3 (local development):**
- Basic authentication (default admin user)
- No team collaboration features
- Single-user mode

**Phase 4+ (team deployment):**
- LDAP/SSO integration
- Role-based access control
- Audit logging

---

## Monitoring and Observability

### Health Checks

All OpenMetadata services include health check endpoints:

```bash
# OpenMetadata Server
curl http://localhost:8585/api/v1/health

# Ingestion Airflow
curl http://localhost:8080/health

# Elasticsearch
curl http://localhost:9200/_cluster/health

# PostgreSQL
docker exec openmetadata-postgres pg_isready
```

### Logs

Centralized logging via Docker Compose:

```bash
# All OpenMetadata logs
make openmetadata-logs

# Specific service
docker logs openmetadata-ingestion -f

# Grep for errors
docker logs openmetadata-server 2>&1 | grep ERROR
```

### Resource Monitoring

OpenMetadata stack resource requirements:

| Service | Memory | CPU | Storage |
|---------|--------|-----|---------|
| Server | 2GB | 1 core | 1GB |
| Ingestion | 2GB | 1 core | 1GB |
| Elasticsearch | 2GB | 1 core | 10GB |
| PostgreSQL | 512MB | 0.5 core | 5GB |
| **Total** | **6.5GB** | **3.5 cores** | **17GB** |

**Recommendation:** 8GB RAM minimum for developer workstation

---

## Testing Strategy

### Unit Tests (Not Applicable)

OpenMetadata is a third-party application, no custom code to unit test.

### Integration Tests

Test that OpenMetadata integrates correctly with platform:

```bash
# platform-bootstrap/tests/test-openmetadata-integration.sh

#!/bin/bash
set -e

# 1. Test: Services start successfully
make openmetadata-start
sleep 30  # Wait for initialization

# 2. Test: UI is accessible
curl -f http://localhost:8585/api/v1/health

# 3. Test: Ingestion container has Kerberos ticket
docker exec openmetadata-ingestion klist -s

# 4. Test: Can connect to PostgreSQL
docker exec openmetadata-ingestion psql -h localhost -U openmetadata_user -d openmetadata_db -c "SELECT 1"

# 5. Test: Cleanup works
make openmetadata-stop

echo "✅ All integration tests passed!"
```

### Manual Testing Checklist

**Phase 1:**
- [ ] Start OpenMetadata services
- [ ] Access UI at localhost:8585
- [ ] Create pagila PostgreSQL connection
- [ ] Run metadata ingestion
- [ ] Verify tables appear in UI
- [ ] Search for specific table
- [ ] View table schema details

**Phase 2:**
- [ ] Verify Kerberos ticket in ingestion container
- [ ] Create SQL Server connection (Kerberos)
- [ ] Test connection (should succeed without password)
- [ ] Run metadata ingestion
- [ ] Verify SQL Server tables appear
- [ ] Check authentication method used

**Phase 3:**
- [ ] Create Airflow pipeline service
- [ ] Configure connection to Astronomer
- [ ] Run pipeline ingestion
- [ ] Verify DAGs appear in OpenMetadata
- [ ] Check DAG lineage graph
- [ ] Test lineage operator in sample DAG

---

## Documentation Deliverables

### 1. Design Document (This File)
**Audience:** Technical architects, platform engineers
**Purpose:** Architectural decisions and rationale

### 2. Technical Implementation Spec
**Audience:** Developers implementing the integration
**Purpose:** Step-by-step implementation guide

### 3. Developer Guide
**Audience:** Data engineers using the platform
**Purpose:** How to use OpenMetadata for daily work

**Topics:**
- Connecting to OpenMetadata
- Searching for tables
- Understanding schemas
- Adding lineage to DAGs
- Best practices

### 4. Administrator Guide
**Audience:** Platform administrators
**Purpose:** Operations and maintenance

**Topics:**
- Starting/stopping services
- Configuring data sources
- Troubleshooting common issues
- Backup and restore
- Monitoring and health checks

### 5. Kerberos Integration Guide
**Audience:** Security engineers, platform engineers
**Purpose:** How Kerberos authentication works

**Topics:**
- Architecture overview
- Ticket flow
- Troubleshooting authentication
- Security considerations

---

## Success Metrics

### Technical Metrics
- [ ] Services start successfully on first try
- [ ] UI response time < 2 seconds
- [ ] Metadata ingestion completes in < 5 minutes for pagila
- [ ] Zero authentication errors with Kerberos
- [ ] 100% health check pass rate

### Developer Experience Metrics
- [ ] Developer can set up OpenMetadata in < 15 minutes
- [ ] Can find table schema in < 30 seconds via search
- [ ] Lineage graph renders in < 3 seconds
- [ ] Zero credential management questions (Kerberos works transparently)

### Business Value Metrics (Long-term)
- Reduction in "where is this data?" questions
- Faster onboarding for new team members
- Improved data quality (better understanding of schemas)
- Time saved on impact analysis before changes

---

## Risk Mitigation

### Risk 1: Resource Constraints
**Risk:** OpenMetadata stack requires 6.5GB RAM
**Impact:** May not work on all developer workstations
**Likelihood:** Medium
**Mitigation:**
- Make OpenMetadata optional (not required)
- Document minimum requirements clearly
- Provide lightweight mode (disable Elasticsearch)
- Offer shared team instance as alternative

### Risk 2: Corporate Firewall
**Risk:** OpenMetadata images blocked by corporate proxy
**Impact:** Cannot download images, cannot start services
**Likelihood:** High (in restricted environments)
**Mitigation:**
- Document Artifactory mirror setup
- Setup wizard prompts for corporate image paths
- Test in corporate environment early
- Include troubleshooting guide

### Risk 3: Kerberos Complexity
**Risk:** SQL Server + Kerberos + Container = complex
**Impact:** Authentication failures, difficult debugging
**Likelihood:** Medium
**Mitigation:**
- Start with pagila (no auth) to prove basic functionality
- Reuse existing Kerberos diagnostic tools
- Create dedicated diagnostic script
- Provide detailed troubleshooting guide

### Risk 4: Maintenance Burden
**Risk:** Another service to maintain and support
**Impact:** Increased support load, outdated documentation
**Likelihood:** Medium
**Mitigation:**
- Start as optional/experimental
- Clear documentation for self-service
- Leverage OpenMetadata community
- Only promote to "core platform" after proven

### Risk 5: Version Compatibility
**Risk:** OpenMetadata updates may break integration
**Impact:** Services fail after upgrade
**Likelihood:** Low (semantic versioning)
**Mitigation:**
- Pin specific version in platform-config.yaml
- Test upgrades in isolation
- Document tested versions
- Subscribe to OpenMetadata release notes

---

## Architectural Decisions (CONFIRMED)

### Decision Log - 2025-01-16

The following decisions have been made regarding OpenMetadata integration:

1. **Deployment Model: ALWAYS-ON**
   - **Decision:** OpenMetadata runs as a standard platform service (like Kerberos sidecar)
   - **Rationale:** Consistent with platform pattern, always available for metadata discovery
   - **Implementation:** `make platform-start` includes OpenMetadata by default
   - **Impact:** Makefile targets treat OpenMetadata as core service

2. **Corporate Environment: ARTIFACTORY MIRRORS PROVIDED**
   - **Decision:** IT will provide Artifactory mirrors for OpenMetadata images
   - **Configuration:** Image paths stored in `platform-config.yaml` (managed by setup wizard)
   - **Pattern:** Same as existing Astronomer/Elasticsearch images
   - **Format:**
     ```yaml
     openmetadata:
       images:
         server: artifactory.company.com/path/to/openmetadata/server:1.2.0
         ingestion: artifactory.company.com/path/to/openmetadata/ingestion:1.2.0
     ```

3. **Team Collaboration: DUAL MODE**
   - **Local Development:** Single-user instance on developer workstation
     - Basic authentication
     - No team coordination needed
     - Fast iteration
   - **Above Dev Environments (INT/QA/PROD):** Shared team instance
     - Centralized metadata catalog
     - LDAP/SSO integration (future)
     - Managed by platform team
   - **Migration Path:** Start local, promote metadata to shared instance when ready

4. **Integration Depth: INCREMENTAL + EVERYTHING AS CODE**
   - **Decision:** Build support incrementally via programmatic ingestion DAGs
   - **Phase 1:** Shared infrastructure + programmatic pagila ingestion DAG
   - **Phase 2:** Programmatic SQL Server ingestion DAG (Kerberos!)
   - **Phase 3:** Airflow lineage integration
   - **Phase 4+:** Documentation and patterns (not premature templates)
   - **Rationale:** "Everything as code" culture - no manual UI clicking
   - **Impact:** Skip manual ingestion phase, go straight to DAG-based approach

5. **Scope (Clarified):**
   - **In Scope:** PostgreSQL (pagila), SQL Server (via Kerberos), Airflow lineage
   - **Out of Scope (initially):** Cloud sources, dbt integration
   - **Approach:** Start focused, expand based on team needs

6. **Infrastructure Simplification: 3 SERVICES (NOT 4)**
   - **Decision:** No separate ingestion container, no redundant Airflow
   - **Stack:** Shared PostgreSQL + OpenMetadata Server + Elasticsearch
   - **Ingestion Method:** Astronomer DAGs with OpenMetadata Python SDK
   - **Rationale:**
     * Infrastructure team won't want N Airflow instances
     * Astronomer is THE orchestrator
     * Saves ~2GB RAM
   - **Impact:** Server has Kerberos access for ad-hoc testing, DAGs for production

7. **Database Architecture: OLTP/OLAP SEPARATION**
   - **Decision:** Platform PostgreSQL (OLTP) separate from Warehouse PostgreSQL (OLAP)
   - **Platform PostgreSQL:**
     * `openmetadata_db`, `airflow_db` (future), other platform services
     * Operational/transactional workloads
     * In `platform-bootstrap`
   - **Warehouse PostgreSQL:**
     * Business data, dimensional models, analytical queries
     * Separate instance per datakit/environment
     * NOT in platform-bootstrap
   - **Rationale:** Performance isolation, independent scaling, matches production
   - **Impact:** Clear architecture boundaries, realistic platform pattern

---

## Related Documents

- [Platform Architecture Vision](platform-architecture-vision.md)
- [Getting Started Guide](getting-started-simple.md)
- Technical Implementation Spec (to be created)
- OpenMetadata Developer Guide (to be created)
- Kerberos Integration Guide (to be created)

---

## Changelog

| Date | Change | Author |
|------|--------|--------|
| 2025-01-16 | Initial design document created | Platform Team |

---

## Appendix: OpenMetadata Resources

### Official Documentation
- [OpenMetadata Docs](https://docs.open-metadata.org/)
- [Docker Deployment Guide](https://docs.open-metadata.org/latest/quick-start/local-docker-deployment)
- [MSSQL Connector](https://docs.open-metadata.org/latest/connectors/database/mssql)
- [Airflow Integration](https://docs.open-metadata.org/latest/connectors/pipeline/airflow)

### Community
- [Slack Community](https://slack.open-metadata.org/)
- [GitHub Repository](https://github.com/open-metadata/OpenMetadata)
- [GitHub Discussions](https://github.com/open-metadata/OpenMetadata/discussions)

### Learning Resources
- [OpenMetadata Tutorials](https://docs.open-metadata.org/latest/tutorials)
- [Video Demos](https://www.youtube.com/@open-metadata)
- [Blog Posts](https://blog.open-metadata.org/)
