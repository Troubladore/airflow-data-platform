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

## Image Variables and Requirements

### 1. IMAGE_PYTHON (Python Runtime)
**Default:** `python:3.11-alpine`
**Used for:** General Python execution, DAG processing

**Requirements:**
- Python 3.11+
- Shell: `/bin/sh` or `/bin/bash`
- Package manager: `apk` (Alpine) or `apt` (Debian/Ubuntu)
- Ability to install packages at runtime

**Current Usage:**
```bash
# Platform expects to be able to run:
docker run IMAGE_PYTHON sh -c "commands"
```

### 2. IMAGE_KERBEROS_TEST (Kerberos Validation)
**Default:** Same as IMAGE_PYTHON (`python:3.11-alpine`)
**Used for:** Kerberos ticket validation during setup

**Requirements (Layered Mode):**
- Python 3.11+
- Shell: `/bin/sh` or `/bin/bash`
- Package manager: `apk` (Alpine) or `apt` (Debian/Ubuntu)
- Must be able to install `krb5` packages at runtime
- Must be able to mount and read from volumes

**Requirements (Prebuilt Mode):**
- Python 3.11+
- Shell: `/bin/sh` or `/bin/bash`
- `krb5` packages pre-installed
- Must be able to mount and read from volumes

**Usage by Mode:**
```bash
# Layered mode - installs krb5 at runtime:
docker run IMAGE_KERBEROS_TEST sh -c "apk add krb5 && python /app/test.py"

# Prebuilt mode - expects krb5 already installed:
docker run IMAGE_KERBEROS_TEST sh -c "python /app/test.py"
```

### 3. IMAGE_POSTGRES (PostgreSQL Database)
**Default:** `postgres:17.5-alpine`
**Used for:** Platform PostgreSQL, Pagila database

**Requirements:**
- PostgreSQL 17.5+
- Standard PostgreSQL environment variables support
- `/docker-entrypoint-initdb.d/` script execution
- Volume mounting for data persistence

### 4. IMAGE_OPENMETADATA_SERVER (OpenMetadata)
**Default:** `docker.getcollate.io/openmetadata/server:1.10.1`
**Used for:** Metadata catalog service

**Requirements:**
- OpenMetadata 1.10.1
- Java runtime
- Standard OpenMetadata environment variables

### 5. IMAGE_OPENSEARCH (Search Engine)
**Default:** `opensearchproject/opensearch:2.19.2`
**Used for:** OpenMetadata backend search

**Requirements:**
- OpenSearch 2.19.2
- Java runtime
- Standard OpenSearch configuration support

## Sample Dockerfiles for Custom Images

### Python Runtime with Custom Requirements

```dockerfile
# docs/dockerfiles/python-runtime/Dockerfile
FROM python:3.11-alpine

# REQUIRED: Shell must be available
# Already present in python:3.11-alpine

# Custom additions (optional)
# Add CA certificates if needed (for corporate environments)
COPY ca-certificates.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Pre-install common packages to reduce runtime delays
RUN apk add --no-cache \
    gcc \
    musl-dev \
    libffi-dev \
    openssl-dev

# Configure pip for private PyPI (if using)
RUN pip config set global.index-url https://pypi.yourorg.com/simple
RUN pip config set global.trusted-host pypi.yourorg.com

# IMPORTANT: Keep shell and package manager available
# Platform will run: sh -c "pip install X" at runtime
```

### Kerberos Test Image

```dockerfile
# docs/dockerfiles/kerberos-test/Dockerfile
FROM python:3.11-alpine

# REQUIRED: Shell and package manager
# Platform needs to run: sh -c "apk add krb5"

# Custom requirements (optional)
COPY ca-certificates.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Pre-install krb5 to speed up testing (optional optimization)
RUN apk add --no-cache krb5 krb5-libs

# Add any custom Kerberos configurations
COPY krb5.conf /etc/krb5.conf

# IMPORTANT: Must retain ability to run shell commands
# Platform will run: sh -c "commands"
```

### PostgreSQL with Extensions

```dockerfile
# docs/dockerfiles/postgres-custom/Dockerfile
FROM postgres:17.5-alpine

# PostgreSQL already meets all requirements
# Add corporate customizations

# Install additional extensions
RUN apk add --no-cache \
    postgresql-contrib \
    postgresql-plpython3

# Add corporate CA certificates
COPY corporate-ca.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Custom configurations
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY pg_hba.conf /etc/postgresql/pg_hba.conf

# IMPORTANT: Preserve PostgreSQL's entrypoint behavior
# Must support /docker-entrypoint-initdb.d/ scripts
```

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

### Issue: "sh: not found"
**Solution:** Your image must include a shell. Add `RUN apk add --no-cache bash` or ensure `/bin/sh` exists.

### Issue: "apk: not found"
**Solution:** If using a non-Alpine base, the platform detects and uses `apt` instead. Ensure one package manager is available.

### Issue: Kerberos test fails
**Solution:** Ensure the image can install or has pre-installed `krb5` packages.

## Summary

The platform currently requires:
1. **Shell access** (`/bin/sh` or `/bin/bash`)
2. **Package manager** for runtime installation
3. **Standard volume mounting** capabilities
4. **Environment variable** support

Future versions may support distroless/minimal images, but current version requires these capabilities.

## Sample Dockerfiles

Ready-to-use Dockerfile templates for each image type:
- [Kerberos Test Image](dockerfiles/kerberos-test.md) - For validating ticket sharing
- [Python Runtime Image](dockerfiles/python-runtime.md) - For DAGs and general Python execution
- [PostgreSQL Custom Image](dockerfiles/postgres-custom.md) - For database with custom configurations