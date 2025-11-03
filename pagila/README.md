# Pagila Sample Database Service

A PostgreSQL sample database for testing and development, featuring a DVD rental store schema with realistic data relationships.

## Overview

Pagila is a port of the Sakila sample database (originally designed for MySQL) to PostgreSQL. It provides:
- **Sample schema** - Complete DVD rental business model
- **Realistic data** - Thousands of records across multiple tables
- **Complex relationships** - Foreign keys, many-to-many relationships, views
- **Testing ground** - Perfect for testing queries, ETL pipelines, and data tools

## Quick Start

The Pagila service is typically installed through the platform wizard:

```bash
./platform setup pagila
```

For manual setup:
```bash
./scripts/setup-pagila.sh
```

## Architecture

### Database Schema

Pagila includes the following main tables:
- **actor** - Film actors
- **film** - Film catalog
- **customer** - Customer records
- **rental** - Rental transactions
- **payment** - Payment records
- **store** - Store locations
- **staff** - Employee records
- **inventory** - Film inventory

### Container Setup

Pagila runs in its own PostgreSQL container (`pagila-postgres`) separate from the platform database to ensure isolation of sample data from production systems.

## Connection Information

**From other Docker containers:**
```
Host: pagila-postgres
Port: 5432
Database: pagila
User: postgres
Password: postgres
```

**From host machine:**
```
Host: localhost
Port: 5433 (mapped from container's 5432)
Database: pagila
User: postgres
Password: postgres
```

## Test Containers

Test containers provide lightweight database clients for verifying Pagila connectivity and data loads. They are essential for validating database access before deploying workloads.

### pagila-test Specifications

The Pagila test container provides a minimal Alpine environment with PostgreSQL client tools.

**Features:**
- PostgreSQL 17 client (psql) for database queries
- Minimal Alpine base for small image size (~15MB)
- Runs as non-root user (testuser, uid 10001) for security
- Customizable base image via `BASE_IMAGE` build argument

**Installed Packages:**
- `postgresql17-client`: PostgreSQL command-line tools
- `ca-certificates`: SSL CA certificates
- `tzdata`: Timezone data

**Security:**
The container runs as a non-root user (testuser, uid 10001) following the principle of least privilege. No credentials or secrets are included in the image.

### Configuration via Wizard

Test containers are configured through the pagila wizard during setup. The wizard asks:
1. Whether to use a prebuilt test image
2. Which Docker image to use as the base

**Configuration Variables:**
- `IMAGE_PAGILA_TEST`: Docker image for pagila-test container
- `PAGILA_TEST_PREBUILT`: Whether to use prebuilt mode (true/false)

These variables are stored in `platform-bootstrap/.env` and used by the build system.

### Build Modes

The pagila-test container supports two build modes:

**Build Mode (PAGILA_TEST_PREBUILT=false, default):**
- Builds from a base image (e.g., alpine:latest)
- Adds PostgreSQL client at build time
- More flexible but requires package installation
- Default: Uses `alpine:latest` as base

**Prebuilt Mode (PAGILA_TEST_PREBUILT=true):**
- Uses a prebuilt image from corporate registry
- Image must already contain required packages
- Faster startup but requires configured corporate images
- Example: `artifactory.company.com/docker/pagila-test:2025.1`

### Usage Examples

Build the test container:
```bash
make build-pagila-test
```

Test Pagila connection:
```bash
make test-connection
```

Run custom queries:
```bash
docker run --rm --network platform_network platform/pagila-test:latest \
  psql -h pagila-postgres -U postgres -d pagila \
  -c "SELECT COUNT(*) FROM film;"
```

Check table structure:
```bash
docker run --rm --network platform_network platform/pagila-test:latest \
  psql -h pagila-postgres -U postgres -d pagila \
  -c "\d+ film"
```

## Sample Queries

### Basic Queries

List all films:
```sql
SELECT title, release_year, rating FROM film LIMIT 10;
```

Find customers with overdue rentals:
```sql
SELECT c.first_name, c.last_name, r.return_date
FROM customer c
JOIN rental r ON c.customer_id = r.customer_id
WHERE r.return_date < CURRENT_DATE
  AND r.return_date IS NOT NULL;
```

### Analytics Queries

Top revenue-generating films:
```sql
SELECT f.title, SUM(p.amount) as total_revenue
FROM film f
JOIN inventory i ON f.film_id = i.film_id
JOIN rental r ON i.inventory_id = r.inventory_id
JOIN payment p ON r.rental_id = p.rental_id
GROUP BY f.film_id, f.title
ORDER BY total_revenue DESC
LIMIT 10;
```

Customer lifetime value:
```sql
SELECT
  c.customer_id,
  c.first_name || ' ' || c.last_name as customer_name,
  COUNT(DISTINCT r.rental_id) as rental_count,
  SUM(p.amount) as lifetime_value
FROM customer c
LEFT JOIN rental r ON c.customer_id = r.customer_id
LEFT JOIN payment p ON r.rental_id = p.rental_id
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY lifetime_value DESC;
```

## Troubleshooting

### Container Won't Start

Check if port 5433 is already in use:
```bash
lsof -i :5433
```

Check container logs:
```bash
docker logs pagila-postgres
```

### Database Not Accessible

Verify container is running:
```bash
docker ps | grep pagila-postgres
```

Test connection with pagila-test container:
```bash
make test-connection
```

### Data Not Loaded

The Pagila setup script should automatically:
1. Create the database
2. Load the schema
3. Insert sample data

If data is missing, check setup logs:
```bash
docker exec pagila-postgres psql -U postgres -d pagila -c "\dt"
```

### Reset Database

To completely reset Pagila:
```bash
docker stop pagila-postgres
docker rm pagila-postgres
docker volume rm pagila_postgres_data
./scripts/setup-pagila.sh
```

## Integration with Airflow

Pagila can be used as a source for Airflow DAGs. Add this connection in Airflow:

- **Connection ID**: `pagila_db`
- **Connection Type**: `Postgres`
- **Host**: `pagila-postgres`
- **Schema**: `pagila`
- **Login**: `postgres`
- **Password**: `postgres`
- **Port**: `5432`

Example DAG usage:
```python
from airflow.providers.postgres.hooks.postgres import PostgresHook

def extract_film_data(**context):
    pg_hook = PostgresHook(postgres_conn_id='pagila_db')
    df = pg_hook.get_pandas_df(sql="SELECT * FROM film LIMIT 100")
    return df
```

## Resources

- [Original Pagila Repository](https://github.com/devrimgunduz/pagila)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Sample Queries and Exercises](https://github.com/devrimgunduz/pagila/tree/master/sql)