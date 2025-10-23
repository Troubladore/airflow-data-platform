# PostgreSQL Custom Image Dockerfile

## What Is This Image For?

The PostgreSQL image serves as the database foundation for the platform, with three distinct use cases:
- **Platform PostgreSQL**: Hosts OpenMetadata and Airflow metadata (admin OLTP)
- **Pagila Database**: Provides sample data for testing and examples (app OLTP)
- **Warehouse PostgreSQL**: Stores business data in Bronze/Silver/Gold layers (OLAP)

This image must support standard PostgreSQL operations while meeting corporate security, performance, and compliance requirements. The same base image can be configured differently for each use case.

## Requirements

### Standard Requirements (All Images)
- **PostgreSQL Version**: 17.5+ (latest stable)
- **Environment Variables**: Support POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB, POSTGRES_HOST_AUTH_METHOD
- **Initialization**: Execute scripts in `/docker-entrypoint-initdb.d/`
- **Volume Support**: Data persistence at `/var/lib/postgresql/data`
- **Tools**: Include psql, pg_dump, pg_restore for operations

### Corporate Requirements (Optional)
- **CA Certificates**: Corporate certificate chain for SSL connections
- **Authentication**: Support for SCRAM-SHA-256, LDAP, or Kerberos
- **Audit Logging**: pgaudit extension for compliance
- **Monitoring**: pg_stat_statements for performance tracking

## Alpine-Based Dockerfiles

<details>
<summary><b>Option 1: Standard Alpine PostgreSQL</b> - Minimal production image</summary>
```dockerfile
# Minimal PostgreSQL with standard extensions
FROM postgres:17.5-alpine

# No additional setup needed for basic use
# Uses standard PostgreSQL entrypoint and configuration
```

**Alpine Version**: PostgreSQL 17.5 runs on Alpine 3.19
**Size**: ~240MB (very lightweight)
**Configure**: `IMAGE_POSTGRES=postgres:17.5-alpine`
**Use Case**: Development, testing, simple deployments

</details>

<details>
<summary><b>Option 2: Alpine with Extensions</b> - Enhanced functionality</summary>

```dockerfile
# Add common extensions to standard PostgreSQL
FROM postgres:17.5-alpine

# Install additional extensions
RUN apk add --no-cache \
    postgresql-contrib \
    postgresql-plpython3 \
    postgresql-plperl

# Add custom configurations for performance
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY pg_hba.conf /etc/postgresql/pg_hba.conf

# Note: Preserves standard PostgreSQL entrypoint
```

**Extensions**: contrib (pg_stat_statements, pgcrypto), plpython3, plperl
**Build**: `docker build -t myorg/postgres:17.5-alpine-extended -f Dockerfile.postgres .`
**Configure**: `IMAGE_POSTGRES=myorg/postgres:17.5-alpine-extended`

</details>

<details>
<summary><b>Option 3: Corporate Hardened Alpine</b> - Enterprise security requirements</summary>
```dockerfile
# Security-hardened PostgreSQL for corporate use
FROM postgres:17.5-alpine

# Add corporate CA certificates
COPY corporate-ca.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Install required extensions including pgaudit
RUN apk add --no-cache \
    postgresql-contrib \
    postgresql-plpgsql \
    postgresql-client \
    postgresql-pgaudit

# Security configurations
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY pg_hba.conf /etc/postgresql/pg_hba.conf

# Set secure defaults
ENV POSTGRES_INITDB_ARGS="--auth-host=scram-sha-256 --auth-local=trust"
ENV POSTGRES_HOST_AUTH_METHOD=scram-sha-256

# Create audit log directory
RUN mkdir -p /var/log/postgresql && \
    chown postgres:postgres /var/log/postgresql

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s \
    CMD pg_isready -U postgres || exit 1
```

**Security Features**: SCRAM-SHA-256 auth, pgaudit logging, health checks
**Build**: `docker build -t myorg/postgres:17.5-alpine-hardened -f Dockerfile.postgres .`
**Compliance**: SOC2, HIPAA audit requirements met

</details>

<details>
<summary><b>Option 4: Alpine with Monitoring</b> - Performance observability</summary>
```dockerfile
# PostgreSQL with built-in monitoring
FROM postgres:17.5-alpine

# Install monitoring extensions
RUN apk add --no-cache \
    postgresql-contrib \
    postgresql-pg-stat-kcache \
    postgresql-pgaudit

# Add monitoring scripts
COPY monitoring-setup.sql /docker-entrypoint-initdb.d/10-monitoring.sql

# Configure for monitoring
ENV POSTGRES_DB=postgres
ENV POSTGRES_SHARED_PRELOAD_LIBRARIES="pg_stat_statements,pgaudit"

# Custom postgresql.conf with monitoring settings
COPY postgresql.conf /etc/postgresql/postgresql.conf
```

**Monitoring**: pg_stat_statements, pg_stat_kcache, pgaudit
**Build**: `docker build -t myorg/postgres:17.5-alpine-monitoring -f Dockerfile.postgres .`
**Use Case**: Production databases requiring performance insights

</details>

## Ubuntu/Debian-Based Dockerfiles

<details>
<summary><b>Option 5: Standard Ubuntu PostgreSQL</b> - Debian-based alternative</summary>
```dockerfile
# Standard Debian/Ubuntu PostgreSQL
FROM postgres:17.5-bookworm

# No additional setup for basic use
# Debian provides broader compatibility than Alpine
```

**OS Version**: Debian 12 (Bookworm) base
**Size**: ~380MB (larger than Alpine but more compatible)
**Configure**: `IMAGE_POSTGRES=postgres:17.5-bookworm`
**Advantages**: Better glibc compatibility, more packages available

</details>

<details>
<summary><b>Option 6: Ubuntu Multi-Database Setup</b> - Platform services configuration</summary>

```dockerfile
# PostgreSQL configured for multiple platform databases
FROM postgres:17.5-bookworm

# Install extensions
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-contrib-17 \
    && rm -rf /var/lib/apt/lists/*

# Add initialization scripts
COPY init-scripts/*.sql /docker-entrypoint-initdb.d/
COPY init-scripts/*.sh /docker-entrypoint-initdb.d/

# Script to create multiple databases
RUN cat > /docker-entrypoint-initdb.d/01-create-databases.sh << 'EOF'
#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE openmetadata_db;
    CREATE DATABASE airflow_db;
    CREATE DATABASE analytics_db;

    CREATE USER openmetadata_user WITH PASSWORD '$OPENMETADATA_DB_PASSWORD';
    CREATE USER airflow_user WITH PASSWORD '$AIRFLOW_DB_PASSWORD';

    GRANT ALL PRIVILEGES ON DATABASE openmetadata_db TO openmetadata_user;
    GRANT ALL PRIVILEGES ON DATABASE airflow_db TO airflow_user;

    -- Enable extensions
    \c openmetadata_db
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

    \c airflow_db
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOSQL
EOF

RUN chmod +x /docker-entrypoint-initdb.d/01-create-databases.sh
```

**Build**: `docker build -t myorg/postgres:17.5-multidb -f Dockerfile.postgres .`
**Configure**: `IMAGE_POSTGRES=myorg/postgres:17.5-multidb`
**Purpose**: Single PostgreSQL instance for all platform services

</details>

<details>
<summary><b>Option 7: Ubuntu with TimescaleDB</b> - Time-series data support</summary>

```dockerfile
# PostgreSQL with TimescaleDB for time-series data
FROM timescale/timescaledb:latest-pg17

# Add corporate certificates
COPY corporate-ca.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Enable TimescaleDB
RUN echo "shared_preload_libraries = 'timescaledb'" >> /usr/share/postgresql/postgresql.conf.sample

# Add initialization to create hypertables
COPY timescale-init.sql /docker-entrypoint-initdb.d/20-timescale.sql
```

**Build**: `docker build -t myorg/postgres:17.5-timescale -f Dockerfile.postgres .`
**Use Case**: IoT data, metrics, logs, any time-series workload
**Extensions**: TimescaleDB for automatic partitioning and compression

</details>

## Authentication Modes

### Password-less Development Setup

PostgreSQL images support password-less authentication for development environments using the `POSTGRES_HOST_AUTH_METHOD` environment variable:

```bash
# Trust all connections (DEVELOPMENT ONLY - NEVER USE IN PRODUCTION!)
docker run -d \
  --name postgres-dev \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  -p 5432:5432 \
  postgres:17.5-alpine

# Connect without password
psql -h localhost -U postgres
```

**Available Authentication Methods:**
- `trust` - Allow connections without password (development only)
- `reject` - Reject all connections
- `md5` - Require MD5-encrypted password (legacy)
- `scram-sha-256` - Require SCRAM-encrypted password (recommended for production)
- `password` - Require plain-text password (not recommended)

**Security Warning**: Never use `trust` authentication in production or on publicly accessible systems!

### Dockerfile for Development (Password-less)

<details>
<summary><b>Development PostgreSQL with Trust Authentication</b> - Local development only</summary>

```dockerfile
# PostgreSQL for local development - NO PASSWORD REQUIRED
FROM postgres:17.5-alpine

# Set trust authentication for all connections
ENV POSTGRES_HOST_AUTH_METHOD=trust

# Create default databases for development
RUN cat > /docker-entrypoint-initdb.d/01-create-dev-databases.sh << 'EOF'
#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "postgres" <<-EOSQL
    CREATE DATABASE dev_db;
    CREATE DATABASE test_db;
    CREATE DATABASE integration_db;

    CREATE USER developer;
    GRANT ALL PRIVILEGES ON DATABASE dev_db TO developer;
    GRANT ALL PRIVILEGES ON DATABASE test_db TO developer;
EOSQL
EOF

RUN chmod +x /docker-entrypoint-initdb.d/01-create-dev-databases.sh

# Add development-friendly settings
RUN cat > /docker-entrypoint-initdb.d/02-dev-settings.sql << 'EOF'
-- Enable all statement logging for development
ALTER SYSTEM SET log_statement = 'all';
ALTER SYSTEM SET log_duration = 'on';
EOF
```

**Build**: `docker build -t myorg/postgres:17.5-dev-noauth -f Dockerfile.postgres .`
**Use**: `docker run -d -p 5432:5432 myorg/postgres:17.5-dev-noauth`
**Connect**: `psql -h localhost -U postgres` (no password needed)

</details>

## Configuration Files

### postgresql.conf Example
```conf
# Performance tuning
shared_buffers = 256MB
work_mem = 4MB
maintenance_work_mem = 64MB

# Logging
logging_collector = on
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d.log'
log_rotation_age = 1d
log_rotation_size = 100MB

# Connection settings
max_connections = 200
```

### pg_hba.conf Example
```conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
host    all             all             0.0.0.0/0               scram-sha-256
```

## Building and Testing

### Build the Image
```bash
docker build -t myorg/postgres:17.5-custom -f Dockerfile.postgres .
```

### Test Basic Functionality
```bash
# Test PostgreSQL starts
docker run --rm \
    -e POSTGRES_PASSWORD=testpass \
    myorg/postgres:17.5-custom \
    postgres --version

# Test with initialization
docker run --rm \
    -e POSTGRES_PASSWORD=testpass \
    -e POSTGRES_DB=testdb \
    myorg/postgres:17.5-custom
```

### Test Password-less Mode
```bash
# Run with trust authentication (development only)
docker run --rm -d \
    --name test-postgres \
    -e POSTGRES_HOST_AUTH_METHOD=trust \
    -p 5432:5432 \
    myorg/postgres:17.5-custom

# Connect without password
docker exec -it test-postgres psql -U postgres -c "SELECT version();"

# Cleanup
docker stop test-postgres
```

### Test Init Scripts
```bash
# Create test init script
echo "CREATE TABLE test (id INT);" > test-init.sql

# Run with init script
docker run --rm \
    -e POSTGRES_PASSWORD=testpass \
    -v $(pwd)/test-init.sql:/docker-entrypoint-initdb.d/test.sql \
    myorg/postgres:17.5-custom
```

## Configuration

In `platform-bootstrap/.env`:

```bash
# Standard PostgreSQL with password
IMAGE_POSTGRES=postgres:17.5-alpine

# Corporate hardened
IMAGE_POSTGRES=myorg/postgres:17.5-hardened

# With monitoring
IMAGE_POSTGRES=myorg/postgres:17.5-monitoring

# Development without password (add to docker-compose.yml)
# environment:
#   POSTGRES_HOST_AUTH_METHOD: trust
```

### Docker Compose Configuration Examples

```yaml
# Production - with password
services:
  postgres:
    image: ${IMAGE_POSTGRES:-postgres:17.5-alpine}
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_USER: ${DB_USER:-postgres}
      POSTGRES_DB: ${DB_NAME:-myapp}

# Development - password-less
services:
  postgres-dev:
    image: ${IMAGE_POSTGRES:-postgres:17.5-alpine}
    environment:
      POSTGRES_HOST_AUTH_METHOD: trust
      POSTGRES_USER: postgres
      POSTGRES_DB: dev_db
    ports:
      - "5432:5432"
```

## Common Issues

### Issue: Init scripts not running
Init scripts only run on first startup with empty data directory. Remove volume to re-run.

### Issue: Connection refused
Check pg_hba.conf allows connections from the Docker network.

### Issue: Performance problems
Tune postgresql.conf based on available resources.

## Security Considerations

1. **Use SCRAM-SHA-256** authentication instead of md5
2. **Restrict network access** in pg_hba.conf
3. **Enable SSL** for network connections
4. **Regular backups** with proper encryption
5. **Audit logging** with pgaudit extension

## Notes

- The image must preserve PostgreSQL's standard entrypoint behavior
- Init scripts in `/docker-entrypoint-initdb.d/` run alphabetically
- Environment variables like POSTGRES_PASSWORD must be respected
- Data directory is typically mounted at `/var/lib/postgresql/data`
- The platform expects standard PostgreSQL port 5432