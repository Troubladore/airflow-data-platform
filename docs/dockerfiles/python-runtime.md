# Python Runtime Image Dockerfile

## What Is This Image For?

The Python runtime image serves as the general-purpose Python execution environment across the platform. It's used for:
- **Airflow DAG processing**: Parsing and executing workflow definitions
- **Data transformation scripts**: Running ETL/ELT Python code
- **Testing and validation**: Executing pytest suites and data quality checks
- **Utility scripts**: Platform maintenance and operational tasks

This image must balance flexibility (ability to install packages) with security (corporate compliance) and performance (fast startup times).

## Requirements by Mode

### Layered Mode (Default)
- **Base**: Python 3.11+ with shell and pip
- **Runtime**: Can install packages dynamically as needed
- **Use Case**: Development, rapid prototyping, flexible environments
- **Pros**: Works with standard Python images, adapts to any requirements
- **Cons**: Slower startup, requires internet/proxy access, less predictable

### Prebuilt Mode
- **Base**: Python 3.11+ with pre-installed common packages
- **Runtime**: No package installation, all dependencies included
- **Use Case**: Production, validated environments, air-gapped systems
- **Pros**: Fast startup, predictable behavior, security validated
- **Cons**: Less flexible, requires rebuilding for new packages

## Alpine-Based Dockerfiles

<details>
<summary><b>Option 1: Minimal Alpine (Layered Mode)</b> - Lightweight development image</summary>
```dockerfile
# Basic Python image for development
FROM python:3.11-alpine

# Add commonly needed build tools for compiling packages
RUN apk add --no-cache \
    gcc \
    musl-dev \
    libffi-dev \
    openssl-dev \
    make

# For corporate environments - add CA certificates
COPY corporate-ca.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Configure pip for corporate PyPI
ARG PIP_INDEX_URL=https://pypi.org/simple
ENV PIP_INDEX_URL=${PIP_INDEX_URL}
```

**Alpine Version**: 3.18+ recommended for Python 3.11 compatibility
**Size**: ~50MB base + build tools
**Configure**: `IMAGE_PYTHON=python:3.11-alpine`

</details>

<details>
<summary><b>Option 2: Alpine Data Science (Prebuilt Mode)</b> - With common data packages</summary>
```dockerfile
# Alpine with data science packages pre-installed
FROM python:3.11-alpine

# Install build dependencies and PostgreSQL client
RUN apk add --no-cache \
    gcc \
    musl-dev \
    libffi-dev \
    openssl-dev \
    postgresql-dev \
    g++ \
    make

# Pre-install common data packages
RUN pip install --no-cache-dir \
    pandas \
    numpy \
    requests \
    sqlalchemy \
    psycopg2-binary

# Add corporate certificates
COPY corporate-ca.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Clean up build dependencies to reduce size
RUN apk del gcc g++ make musl-dev
```

**Build**: `docker build -t myorg/python:3.11-alpine-data -f Dockerfile.python .`
**Configure**: `IMAGE_MODE=prebuilt` and `IMAGE_PYTHON=myorg/python:3.11-alpine-data`
**Package Notes**: Pre-installed pandas, numpy for data processing

</details>

<details>
<summary><b>Option 3: Corporate Hardened Alpine</b> - Security-focused enterprise image</summary>
```dockerfile
# Security-focused image for production
FROM python:3.11-alpine

# Install build dependencies
RUN apk add --no-cache \
    gcc \
    musl-dev \
    libffi-dev \
    openssl-dev \
    postgresql-dev

# Add corporate CA certificates
COPY corporate-ca.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Configure pip for corporate repository
RUN pip config set global.index-url https://pypi.company.com/simple && \
    pip config set global.trusted-host pypi.company.com

# Install security tools
RUN pip install --no-cache-dir \
    safety \
    bandit

# Create non-root user
RUN adduser -D -u 1000 -s /bin/sh appuser

# Clean up
RUN rm -rf /root/.cache && \
    find / -type f -name "*.pyc" -delete 2>/dev/null || true

USER appuser
WORKDIR /app
```

**Security Features**: Non-root user, vulnerability scanning tools, clean caches
**Build**: `docker build -t myorg/python:3.11-alpine-hardened -f Dockerfile.python .`
**Compliance**: Meets enterprise security requirements

</details>

## Ubuntu/Debian-Based Dockerfiles

<details>
<summary><b>Option 4: Minimal Ubuntu (Layered Mode)</b> - Standard Debian-based image</summary>
```dockerfile
# Minimal Ubuntu/Debian for development
FROM python:3.11-slim-bookworm

# Base image only - packages installed at runtime
# apt-get and shell must be available
```

**OS Versions**: Ubuntu 22.04 (Jammy), Ubuntu 24.04 (Noble), Debian 12 (Bookworm)
**Size**: ~120MB base image
**Configure**: `IMAGE_PYTHON=python:3.11-slim-bookworm`

</details>

<details>
<summary><b>Option 5: Ubuntu Data Science (Prebuilt Mode)</b> - With scientific packages</summary>

```dockerfile
# For data processing and analytics
FROM python:3.11-slim-bookworm

# Install system dependencies for data libraries
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        g++ \
        libpq-dev \
        libssl-dev \
        libffi-dev \
        libxml2-dev \
        libxslt-dev \
    && rm -rf /var/lib/apt/lists/*

# Pre-install common data packages
RUN pip install --no-cache-dir \
    pandas \
    numpy \
    scipy \
    scikit-learn \
    requests \
    sqlalchemy \
    psycopg2-binary

# Add corporate certificates
COPY corporate-ca.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates
```

**Build**: `docker build -t myorg/python:3.11-ubuntu-data -f Dockerfile.python .`
**Configure**: `IMAGE_MODE=prebuilt` and `IMAGE_PYTHON=myorg/python:3.11-ubuntu-data`
**Size**: ~500MB with all data science packages

</details>

<details>
<summary><b>Option 6: Airflow-Compatible Ubuntu</b> - Optimized for DAG execution</summary>

```dockerfile
# Optimized for Airflow DAG execution
FROM python:3.11-slim-bookworm

# Install Airflow dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        g++ \
        libpq-dev \
        libssl-dev \
        libffi-dev \
        libkrb5-dev \
        git \
    && rm -rf /var/lib/apt/lists/*

# Install Airflow providers
RUN pip install --no-cache-dir \
    apache-airflow-providers-postgres \
    apache-airflow-providers-http \
    apache-airflow-providers-ssh

# Add corporate certificates
COPY corporate-ca.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Configure for corporate environment
ENV PYTHONPATH=/opt/airflow/dags:/opt/airflow/plugins
```

**Build**: `docker build -t myorg/python:3.11-airflow -f Dockerfile.python .`
**Configure**: `IMAGE_MODE=prebuilt` and `IMAGE_PYTHON=myorg/python:3.11-airflow`
**Airflow Compatibility**: Includes all common Airflow provider packages

</details>

## Building and Testing

### Build the Image
```bash
docker build -t myorg/python:3.11 -f Dockerfile.python .
```

### Test Basic Functionality
```bash
# Test Python
docker run --rm myorg/python:3.11 python --version

# Test shell
docker run --rm myorg/python:3.11 sh -c "echo 'Shell works'"

# Test pip
docker run --rm myorg/python:3.11 pip list
```

### Test Package Installation
```bash
# Should be able to install packages
docker run --rm myorg/python:3.11 sh -c "pip install requests && python -c 'import requests'"
```

## Configuration

In `platform-bootstrap/.env`:

```bash
# Standard image
IMAGE_PYTHON=python:3.11-alpine

# Corporate image
IMAGE_PYTHON=myorg/python:3.11-corporate

# Data science image
IMAGE_PYTHON=myorg/python:3.11-datascience
```

## Common Issues

### Issue: SSL certificate errors
Add corporate CA certificates and update the certificate store.

### Issue: Cannot install packages
Ensure pip is configured with correct index URL and trusted hosts.

### Issue: C extension compilation fails
Install gcc and development headers (musl-dev for Alpine, build-essential for Debian).

## Performance Tips

1. **Pre-install common packages** to avoid runtime installation
2. **Use multi-stage builds** to reduce final image size
3. **Cache pip downloads** with `--mount=type=cache`
4. **Use slim base images** when possible

## Security Considerations

1. **Regular updates**: Rebuild images regularly for security patches
2. **Vulnerability scanning**: Use tools like Trivy or Snyk
3. **Minimal packages**: Only install what's needed
4. **Non-root user**: Run as non-root when possible

## Notes

- This image is used by multiple services in the platform
- Must maintain compatibility with Airflow requirements
- Shell access is required for current platform operations
- pip must remain functional for dynamic package installation