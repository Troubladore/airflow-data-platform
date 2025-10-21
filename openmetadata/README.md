# OpenMetadata - Standalone Metadata Catalog

Data discovery and governance platform for your data assets.

## Overview

OpenMetadata provides:
- **Metadata catalog** - Discover databases, tables, schemas
- **Data lineage** - Track data flow and transformations
- **Data quality** - Profile and validate data
- **Collaboration** - Tag, describe, and discuss data assets

## Quick Start

```bash
# 1. Configure
cp .env.example .env
# Edit passwords in .env (PLATFORM_DB_PASSWORD, OPENMETADATA_DB_PASSWORD)

# 2. Start
make start

# 3. Access
open http://localhost:8585
# Login: admin@open-metadata.org / admin
```

## Architecture

**Services:**
- `platform-postgres` - PostgreSQL database (contains openmetadata_db)
- `openmetadata-elasticsearch` - Search and indexing
- `openmetadata-server` - UI, API, and connectors

**Standalone:** No external dependencies. Connects to other services via Docker networks.

## Usage

```bash
make start     # Start OpenMetadata
make stop      # Stop OpenMetadata
make status    # Check service health
make logs      # View service logs
make clean     # Remove (WARNING: deletes all metadata!)
```

## Connecting Data Sources

### PostgreSQL (e.g., Pagila)

1. In OpenMetadata UI, go to Settings → Databases → Add Database
2. Select PostgreSQL
3. Configure:
   - Host: `pagila-postgres` (if on same Docker network)
   - Port: `5432`
   - Database: `pagila`
   - Username: `postgres`
   - Password: (trust auth - leave empty)

### Via Airflow DAGs (Recommended)

See `airflow-data-platform-examples/openmetadata-ingestion/` for DAG-based ingestion patterns.

## Configuration

See `.env.example` for all configuration options:
- Ports
- Database passwords
- Corporate image sources (Artifactory)
- Cluster name

## Troubleshooting

**OpenMetadata won't start:**
```bash
make status    # Check service health
make logs      # View error messages
```

**Reset to clean state:**
```bash
make clean     # Removes all containers and volumes
make start     # Fresh installation
```
