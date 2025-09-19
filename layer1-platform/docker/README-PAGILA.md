# Layer 1: Pagila Source Database

This directory provides a self-contained Pagila database for Layer 2 datakit development and testing.

## Quick Start

```bash
# Start Pagila database
./start-pagila-db.sh

# Connect to database
psql -h localhost -p 15432 -U postgres -d pagila

# Stop database
docker compose -f pagila-db.yml down
```

## Architecture Integration

**Purpose**: Provides the "Source A" database referenced in our Layer 2 → Layer 3 data pipeline architecture.

**Layer Integration**:
- **Layer 1** (this): Infrastructure - Pagila PostgreSQL container
- **Layer 2**: Datakits - `pagila-source` (reference schemas) + `pagila-bronze` (warehouse ingestion)
- **Layer 3**: Warehouse orchestration - Airflow DAGs combining Layer 2 components

## Database Details

- **Image**: `bitnami/postgresql:17.2.0` (269MB - security optimized)
- **Port**: `15432` (non-standard to avoid conflicts)
- **Schema**: Full Pagila sample database with film rental data
- **Data**: ~1000 films, customers, rentals for realistic testing
- **Features**: Includes both relational and JSONB extensions
- **Security**: Non-root execution, minimal Photon Linux base, Bitnami hardened image

## Layer 2 Integration

The database is designed to work with Layer 2 datakits:

```bash
# From data-workspace - deploy bronze tables to test target
uv run python data-platform-framework/scripts/deploy_datakit.py \
    ../layer2-datakits/pagila-bronze --target sqlite_memory --validate

# Future: Transform Pagila source → Bronze warehouse
pagila-bronze transform --source-host localhost --source-port 15432 \
    --target-host warehouse --target-schema br__pagila__public
```

## Development Workflow

1. **Start source database**: `./start-pagila-db.sh`
2. **Develop datakits**: Use Layer 2 `pagila-source` schemas for type-safe source reading
3. **Test bronze ingestion**: Use Layer 2 `pagila-bronze` for warehouse pipeline development
4. **Orchestrate**: Use Layer 3 Airflow for end-to-end pipeline testing
