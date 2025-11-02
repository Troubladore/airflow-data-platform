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

## Test Containers

Test containers are lightweight Alpine-based containers that provide database client tools for testing connectivity, authentication, and ODBC driver functionality. They're essential for validating database access in corporate or restricted network environments before deploying actual workloads.

Two types of test containers are available:
- `postgres-test`: PostgreSQL client with Kerberos/GSSAPI support
- `sqlcmd-test`: SQL Server client (FreeTDS-based) with Kerberos support

### postgres-test Specifications

The PostgreSQL test container provides a minimal Alpine environment with PostgreSQL client tools and Kerberos authentication support.

**Features:**
- PostgreSQL 17 client (psql) with GSSAPI/Kerberos authentication support
- Kerberos client libraries for network authentication
- unixODBC support for ODBC-based database connectivity
- Runs as non-root user (testuser, uid 10001) for security
- Customizable base image via `BASE_IMAGE` build argument

**Installed Packages:**
- `postgresql17-client`: PostgreSQL command-line tools
- `krb5`: Kerberos client libraries
- `krb5-libs`: Kerberos shared libraries
- `krb5-conf`: Kerberos configuration files
- `unixodbc`: ODBC driver manager
- `unixodbc-dev`: ODBC development headers
- `ca-certificates`: SSL CA certificates
- `tzdata`: Timezone data

**Security:**
The container runs as a non-root user (testuser, uid 10001) following the principle of least privilege. No hardcoded credentials or secrets are included in the image.

**Customization:**
Supports the `BASE_IMAGE` build argument for corporate environments that require specific base images:
```bash
docker build --build-arg BASE_IMAGE=registry.corp.com/alpine:3.19-hardened -t postgres-test .
```

### sqlcmd-test Specifications

The SQL Server test container provides a minimal Alpine environment with FreeTDS SQL Server client tools and Kerberos authentication support.

**Features:**
- FreeTDS SQL Server client tools (open source alternative to Microsoft mssql-tools)
- Kerberos client libraries for network authentication
- unixODBC support for ODBC-based database connectivity
- Runs as non-root user (testuser, uid 10001) for security
- No Microsoft proprietary tools or EULA requirements
- Customizable base image via `BASE_IMAGE` build argument

**Installed Packages:**
- `freetds`: Open source SQL Server client tools
- `freetds-dev`: FreeTDS development headers
- `krb5`: Kerberos client libraries
- `curl`: Utility for HTTP requests
- `unixodbc`: ODBC driver manager
- `unixodbc-dev`: ODBC development headers

**Security:**
The container runs as a non-root user (testuser, uid 10001) following the principle of least privilege. No hardcoded credentials or secrets are included in the image.

**Note on FreeTDS vs Microsoft Tools:**
FreeTDS provides functionally equivalent SQL Server connectivity to Microsoft's proprietary tools:
- Full T-SQL support via tsql and ODBC interfaces
- Kerberos authentication support
- Microsoft-compatible TDS protocol
- No EULA restrictions
- Better for air-gapped environments (all dependencies from Alpine repos)

### Configuration via Wizard

Test containers are configured through the base_platform wizard as part of the initial platform setup. The wizard asks questions about whether to use prebuilt images and which Docker images to use for each test container.

**Configuration Variables:**
- `IMAGE_POSTGRES_TEST`: Docker image for postgres-test container
- `POSTGRES_TEST_PREBUILT`: Whether to use prebuilt mode (true/false)
- `IMAGE_SQLCMD_TEST`: Docker image for sqlcmd-test container
- `SQLCMD_TEST_PREBUILT`: Whether to use prebuilt mode (true/false)

These variables are stored in `platform-bootstrap/.env` and used by the build system.

### Build Modes

Test containers support two build modes to accommodate different corporate environments:

**Build Mode (PREBUILT=false, default):**
- Builds from a base image (e.g., alpine:latest)
- Adds required packages at build time (krb5, postgresql-client, freetds, etc.)
- More flexible but requires package installation during build
- Default configuration: Uses `alpine:latest` as base

**Prebuilt Mode (PREBUILT=true):**
- Uses a prebuilt image from corporate registry as-is
- Image must already contain all required packages and configurations
- Faster startup but requires properly configured corporate images
- Corporate example: `artifactory.company.com/docker-local/platform/postgres-test:2025.1`

Both containers run as non-root user (testuser, uid 10001) in both build modes.

### Example Commands

```bash
# Build test containers
make build-test-containers

# Test PostgreSQL connection with Kerberos
docker run --rm -v /tmp/krb5cc:/tmp/krb5cc:ro platform/postgres-test:latest psql -h dbserver -U user@REALM -d dbname

# Test SQL Server connection
docker run --rm -v /tmp/krb5cc:/tmp/krb5cc:ro platform/sqlcmd-test:latest sqlcmd -S sqlserver -d database
```

### Kerberos Integration

Test containers support Kerberos authentication for testing authenticated database connections:

**Kerberos Ticket Mounting:**
Mount your Kerberos ticket cache as a read-only volume to enable authentication:
```bash
docker run --rm -v /tmp/krb5cc:/tmp/krb5cc:ro platform/postgres-test:latest psql -h dbserver -U user@REALM -d dbname
```

**Authentication Testing:**
Both containers include Kerberos client libraries and GSSAPI support for testing:
- PostgreSQL: GSSAPI authentication with `-U user@REALM` parameter
- SQL Server: Kerberos authentication with FreeTDS connection strings

**Corporate Environment Support:**
The non-root user design (testuser, uid 10001) enables proper operation in corporate environments with restricted container permissions.
