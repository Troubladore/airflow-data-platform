# Platform Infrastructure README - Test Containers Gap Analysis

## Current State

The current `platform-infrastructure/README.md` documents the core PostgreSQL service and platform network but contains **no information about test containers**. The README covers:
- PostgreSQL service for platform metadata (OpenMetadata, Airflow)
- Platform network for service communication
- Basic usage commands (start, stop, status, logs, clean)
- Connection information and troubleshooting

## Missing Content - Test Containers Section

### 1. Test Containers Overview
**What's missing:** No explanation of what test containers are or why they exist.

**Should include:**
- Test containers are lightweight database client containers for connectivity testing
- Purpose: Validate database connectivity, authentication, and ODBC drivers
- Used for testing PostgreSQL/SQL Server connectivity before deploying workloads
- Support Kerberos authentication, SSL certificate validation, and ODBC connectivity
- Run as non-root users for security

### 2. postgres-test Specifications
**What's missing:** No documentation of the PostgreSQL test container features.

**Should include:**
- **Base Image:** Alpine Linux with configurable base image support
- **Packages Installed:**
  * PostgreSQL 17 client (psql) with GSSAPI support
  * Kerberos client libraries for authentication
  * unixODBC for ODBC-based database connectivity
  * CA certificates and timezone data
- **Security:** Runs as non-root user (testuser, uid 10001)
- **Customization:** Supports BASE_IMAGE build argument for corporate environments
- **Migration Note:** Replaces legacy kerberos/kerberos-sidecar/Dockerfile.postgres-test

### 3. sqlcmd-test Specifications
**What's missing:** No documentation of the SQL Server test container features.

**Should include:**
- **Base Image:** Alpine Linux with configurable base image support
- **Packages Installed:**
  * FreeTDS SQL Server client tools (open source alternative to mssql-tools)
  * Kerberos client libraries for authentication
  * unixODBC for ODBC-based database connectivity
  * curl for utilities
- **Security:** Runs as non-root user (testuser, uid 10001)
- **Customization:** Supports BASE_IMAGE build argument for corporate environments
- **Migration Note:** Replaces legacy kerberos/kerberos-sidecar/Dockerfile.sqlcmd-test
- **FreeTDS vs MSSQL-Tools:** Uses open source FreeTDS instead of Microsoft proprietary tools

### 4. Configuration via Wizard
**What's missing:** No documentation of how test containers are configured through the wizard.

**Should include:**
- Test container configuration is part of the base_platform wizard flow
- Integrated with `test-containers-spec.yaml` sub-specification
- Configuration questions:
  * Whether to use prebuilt postgres-test image
  * Docker image for postgres-test (e.g., alpine:latest or corporate image)
  * Whether to use prebuilt sqlcmd-test image
  * Docker image for sqlcmd-test (e.g., alpine:latest or corporate image)
- State keys stored in configuration:
  * `services.base_platform.test_containers.postgres_test.prebuilt`
  * `services.base_platform.test_containers.postgres_test.image`
  * `services.base_platform.test_containers.sqlcmd_test.prebuilt`
  * `services.base_platform.test_containers.sqlcmd_test.image`

### 5. Build Modes
**What's missing:** No explanation of build vs prebuilt modes.

**Should include:**
- **Build Mode (PREBUILT=false, default):**
  * Builds from Dockerfile using configurable base image
  * Adds required packages at build time (krb5, postgresql-client, freetds, etc.)
  * More flexible but slower startup
- **Prebuilt Mode (PREBUILT=true):**
  * Uses prebuilt image from corporate registry as-is
  * Image must already contain all required packages and configurations
  * Faster startup but requires properly configured corporate images
- Configuration variables:
  * `IMAGE_POSTGRES_TEST`: Base image for postgres-test (default: alpine:latest)
  * `POSTGRES_TEST_PREBUILT`: Use prebuilt image (default: false)
  * `IMAGE_SQLCMD_TEST`: Base image for sqlcmd-test (default: alpine:latest)
  * `SQLCMD_TEST_PREBUILT`: Use prebuilt image (default: false)

### 6. Example Commands for Building and Using
**What's missing:** No practical examples for working with test containers.

**Should include:**
- Building test containers manually:
  ```bash
  # Build postgres-test with defaults
  docker build -t postgres-test platform-infrastructure/test-containers/postgres-test/

  # Build postgres-test with custom base image
  docker build --build-arg BASE_IMAGE=alpine:3.19 -t postgres-test platform-infrastructure/test-containers/postgres-test/

  # Build sqlcmd-test with defaults
  docker build -t sqlcmd-test platform-infrastructure/test-containers/sqlcmd-test/
  ```
- Using test containers for connectivity testing:
  ```bash
  # Test PostgreSQL connectivity
  docker run --rm -it --network platform_network postgres-test psql -h platform-postgres -U platform_admin -d openmetadata_db

  # Test with Kerberos authentication (mount ticket cache)
  docker run --rm -it -v ${KERBEROS_TICKET_DIR}:/tickets:ro --network platform_network postgres-test kinit
  ```

### 7. Integration with Kerberos
**What's missing:** No documentation of Kerberos integration with test containers.

**Should include:**
- Test containers support Kerberos ticket cache mounting for authentication testing
- Both postgres-test and sqlcmd-test include Kerberos client libraries
- GSSAPI authentication support for PostgreSQL and SQL Server
- Example usage with ticket cache mounting:
  ```bash
  # Mount Kerberos ticket cache directory
  docker run --rm -it -v ${KERBEROS_TICKET_DIR}:/tickets:ro --network platform_network postgres-test kinit
  ```
- Requires proper Kerberos configuration in corporate environments

## Success Criteria for Task 8b

To complete the documentation, the `platform-infrastructure/README.md` should include:

1. **New Section:** "Test Containers" explaining what they are and why they exist
2. **Detailed Documentation:** For both postgres-test and sqlcmd-test containers including:
   - Features and capabilities
   - Installed packages
   - Security model (non-root user)
   - Base image customization
3. **Configuration Guide:** How test containers are configured via the wizard
4. **Build Modes Explanation:** Difference between build and prebuilt modes
5. **Practical Examples:** Commands for building and using test containers
6. **Kerberos Integration:** How to use test containers with Kerberos authentication
7. **Corporate Environment Support:** How to configure for corporate base images and prebuilt images

This will bring the README in line with the architecture documentation in `docs/directory-structure.md` and provide users with complete information about all platform infrastructure components.