# Custom Image Requirements

## Overview

This document specifies the exact requirements for custom Docker images used by the Airflow Data Platform. Whether you're building images for corporate environments, security compliance, or just want full control over your dependencies, these images must meet specific requirements for the platform to function correctly.

## Why Use Custom Images?

- **Security**: Pre-scan and approve all dependencies before deployment
- **Performance**: Pre-install packages to avoid runtime downloads and speed up container startup
- **Compliance**: Include corporate certificates, security tools, and audit configurations
- **Reproducibility**: Know exactly what's in your images for consistent deployments
- **Air-gapped Environments**: Work in environments without internet access
- **Private Registries**: Use your organization's private Docker registry

## Image Modes

The platform supports two modes for handling Docker images:

### 1. Layered Mode (Default)
- **Behavior**: Platform installs packages at runtime as needed
- **Flexibility**: Maximum - can use generic base images
- **Performance**: Slower startup (package installation)
- **Use Case**: Development, standard environments

### 2. Prebuilt Mode
- **Behavior**: Platform assumes all dependencies are pre-installed
- **Flexibility**: Limited - images must be complete
- **Performance**: Faster startup (no installation)
- **Use Case**: Production, environments with pre-approved or custom-built images

### How to Use

1. **Build your images** following the Dockerfile examples below
2. **Tag your images** with memorable names (e.g., `myorg/python:3.11-custom`)
3. **Run the setup wizard** (`./dev-tools/setup-kerberos.sh`)
4. **Select "prebuilt" mode** when the wizard asks about image configuration

The wizard handles all configuration automatically - no manual .env editing needed!

## Dockerfile Templates

Ready-to-use templates for each image type with complete requirements and examples:

### Core Images
- **[Python Runtime Image](dockerfiles/python-runtime.md)** - For DAGs and general Python execution
  - Default: `python:3.11-alpine`
  - Alpine and Ubuntu/Debian variants
  - Data science and Airflow-optimized examples

- **[PostgreSQL Base Image](dockerfiles/postgres-base.md)** - Foundation for all platform databases
  - Default: `postgres:17.5-alpine`
  - Used for both Pagila example database and platform service databases
  - Password-less development mode support
  - Multi-database setup examples

- **[Kerberos Test Image](dockerfiles/kerberos-test.md)** - For validating ticket sharing
  - Default: Same as IMAGE_PYTHON
  - Layered vs prebuilt mode examples
  - Corporate hardened variants

### Connectivity Test Containers

These containers are used by the platform to verify database connectivity and are **built automatically** by the wizard during the setup process. You don't need to build them manually - the wizard handles this for you:

- **[PostgreSQL Test Container](../platform-infrastructure/test-containers/postgres-test/Dockerfile)** - Tests PostgreSQL connectivity
  - Base: `alpine:latest`
  - Purpose: Validates platform PostgreSQL database connectivity and health
  - Components: PostgreSQL 17 client (psql), Kerberos client libraries, unixODBC
  - Security: Runs as non-root user (testuser, uid 10001)
  - Build (automatic): The wizard runs `make build-test-containers` during setup
  - Manual build: `docker build -t platform/postgres-test platform-infrastructure/test-containers/postgres-test/`
  - Custom base: `--build-arg BASE_IMAGE=your.registry.com/alpine:3.19`
  - Required for: Health checks during platform setup and PostgreSQL Kerberos testing

- **[SQL Server Test Container](../platform-infrastructure/test-containers/sqlcmd-test/Dockerfile)** - Tests SQL Server connectivity
  - Base: `alpine:latest`
  - Purpose: Validates SQL Server connectivity with Kerberos authentication
  - Components: Microsoft ODBC Driver 18 (msodbcsql18), Microsoft SQL Server tools (mssql-tools18), Kerberos libraries, unixODBC
  - Security: Runs as non-root user (testuser, uid 10001)
  - sqlcmd Location: `/opt/mssql-tools18/bin/sqlcmd` (Microsoft's standard path)
  - Note: Downloads Microsoft ODBC driver APKs from Microsoft's server during build
  - Build (automatic): The wizard runs `make build-test-containers` during setup
  - Manual build: `docker build -t platform/sqlcmd-test platform-infrastructure/test-containers/sqlcmd-test/`
  - Custom base: `--build-arg BASE_IMAGE=your.registry.com/alpine:3.19`
  - Corporate Artifactory: `--build-arg ODBC_DRIVER_URL=https://artifactory.corp.com/mssql-drivers`
  - Required for: SQL Server connectivity validation in Kerberos wizard (PR #151)

### Platform Service Images
By default, the platform pulls from public repositories, but the setup wizard will offer you the chance to specify custom images:

- **OpenMetadata Server** - Metadata catalog service
  - Default: `docker.getcollate.io/openmetadata/server:1.10.1`
  - No special setup needed (runs as-is)
  - Custom images typically only needed for air-gapped environments

- **OpenSearch** - Search and indexing engine
  - Default: `opensearchproject/opensearch:2.19.2`
  - No special setup needed (runs as-is)
  - Custom images typically only needed for air-gapped environments

## Using Your Custom Images

When you run the setup wizard, it will:
1. Ask if you're using custom/corporate images
2. Prompt for your image names (e.g., `myorg/python:3.11-custom`)
3. Ask whether to use "layered" or "prebuilt" mode
4. Configure everything automatically

Example image names you might use:
- **Python runtime**: `myorg/python:3.11-custom`
- **Kerberos test**: `myorg/kerberos-test:3.11-custom`
- **PostgreSQL**: `myorg/postgres:17.5-hardened`
- **OpenMetadata**: `myorg/openmetadata:1.10.1`
- **OpenSearch**: `myorg/opensearch:2.19.2`

## Testing Your Images

### 1. Test Python Runtime Compatibility

```bash
# Test shell availability
docker run --rm myorg/python:3.11 sh -c "echo 'Shell works'"

# Test package installation
docker run --rm myorg/python:3.11 sh -c "pip install requests && python -c 'import requests'"
```

### 2. Test Kerberos Image

```bash
# Test shell and krb5 installation
docker run --rm myorg/kerberos-test:3.11 sh -c "apk add krb5 && klist -V"

# Or if pre-installed:
docker run --rm myorg/kerberos-test:3.11 sh -c "klist -V"
```

### 3. Test PostgreSQL

```bash
# Test basic startup
docker run --rm myorg/postgres:17.5 postgres --version

# Test with environment variables
docker run --rm \
    -e POSTGRES_PASSWORD=test \
    myorg/postgres:17.5
```

## Common Issues and Solutions

<details>
<summary>Click to expand troubleshooting</summary>

### Issue: "sh: not found"
**Solution:** Your image must include a shell. Add `RUN apk add --no-cache bash` or ensure `/bin/sh` exists.

### Issue: "apk: not found"
**Solution:** If using a non-Alpine base, the platform detects and uses `apt` instead. Ensure one package manager is available.

### Issue: Kerberos test fails
**Solution:** Ensure the image can install or has pre-installed `krb5` packages. In prebuilt mode, krb5 must be pre-installed.

### Issue: Package installation fails
**Solution:** Check that your image has internet access or that all required packages are pre-installed in prebuilt mode.

### Issue: PostgreSQL won't start
**Solution:** Ensure you're not overriding the PostgreSQL entrypoint. Custom images must preserve the standard entrypoint behavior.

</details>

## Summary

The platform supports both standard Docker Hub images and custom-built images through two modes:

- **Layered Mode** (default): Installs packages at runtime, works with standard images
- **Prebuilt Mode**: Uses pre-built images with all dependencies, faster and more secure

Key requirements for custom images:
1. **Shell access** (`/bin/sh` or `/bin/bash`)
2. **Package manager** for layered mode (optional for prebuilt)
3. **Standard volume mounting** capabilities
4. **Environment variable** support

The setup wizard handles all configuration automatically - just build your images following the Dockerfile templates and run the wizard!