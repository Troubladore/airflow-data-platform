# Platform Infrastructure - Shared Foundation

The foundational layer for all platform services. Provides shared resources that multiple services depend on.

## Overview

Platform infrastructure is the **always-on foundation** that provides:
- **PostgreSQL (OLTP)** - Shared database for platform services (Airflow metastore, OpenMetadata catalog, etc.)
- **Platform Network** - Shared Docker network for service communication

## Why Separate from Application Services?

**OLTP vs OLAP separation:**
- This PostgreSQL is for **platform metadata** (small, transactional)
- Warehouse PostgreSQL is for **data workloads** (large, analytical)
- Keeps platform operations isolated from data processing

**Multi-tenant platform database:**
- `airflow_db` - Airflow metastore (DAG runs, task instances, etc.)
- `openmetadata_db` - Metadata catalog
- Future platform services get their own databases here

## Quick Start

```bash
# Usually started automatically by platform-bootstrap orchestrator
# But can be run standalone:

cp .env.example .env
make start
```

## Usage

```bash
make start     # Start infrastructure
make stop      # Stop infrastructure
make status    # Check health
make logs      # View logs
make clean     # Remove (WARNING: deletes all platform data!)
```

## Architecture

**This is NOT application infrastructure:**
- ✗ Not for warehouse data (Bronze/Silver/Gold)
- ✗ Not for application databases (like Pagila)
- ✓ Only for platform service metadata

**Services that depend on this:**
- Astronomer Airflow (needs airflow_db)
- OpenMetadata (needs openmetadata_db)
- Future platform services

## Connection Info

**From other Docker containers:**
```
Host: platform-postgres
Port: 5432
User: platform_admin
Password: (set in .env)
```

**Databases created automatically:**
- `openmetadata_db` (owner: openmetadata_user)
- `airflow_db` (owner: airflow_user)

## Troubleshooting

**Infrastructure won't start:**
```bash
make status    # Check current state
make logs      # View PostgreSQL logs
```

**Need to reset:**
```bash
make clean     # WARNING: Deletes all platform databases!
make start     # Fresh installation
```

**Check what databases exist:**
```bash
docker exec platform-postgres psql -U platform_admin -l
```
