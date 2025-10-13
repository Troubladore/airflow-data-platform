# Kerberos Sidecar

Production-ready Kerberos authentication sidecar for Airflow containers, supporting both local development and Kubernetes deployment.

## Purpose

This sidecar container:
- Obtains Kerberos tickets using keytab or password authentication
- Automatically renews tickets before expiration
- Shares tickets with Airflow containers via shared volume
- Enables SQL Server Windows Authentication without passwords

## Quick Start

### Build the Image

**Public internet (default):**
```bash
make build
```

**Corporate Artifactory:**
```bash
# Corporate configuration is in platform-bootstrap/.env (one place!)
# Your DevOps person likely already configured it in your fork

# 1. Verify configuration (already done in fork)
cat ../.env | grep IMAGE_ALPINE

# 2. Login to corporate registry
docker login artifactory.company.com

# 3. Build (uses parent .env automatically)
make build
```

Creates: `platform/kerberos-sidecar:latest` in Docker cache

### Local Development Usage

```bash
# Start with docker-compose
cd ../
docker compose -f developer-kerberos-standalone.yml up -d

# Verify sidecar is running
docker logs kerberos-platform-service

# Check ticket
docker exec kerberos-platform-service klist
```

### Kubernetes/Production Usage

See [Issue #23](https://github.com/Troubladore/airflow-data-platform/issues/23) for Kubernetes deployment patterns.

## Authentication Modes

### Password Authentication (Local Development)

```yaml
# docker-compose.yml
services:
  kerberos-sidecar:
    image: platform/kerberos-sidecar:latest
    environment:
      - KRB_PRINCIPAL=user@COMPANY.COM
      - USE_PASSWORD=true
      - KRB_PASSWORD=your-password  # Or from secret
      - RENEWAL_INTERVAL=3600
```

### Keytab Authentication (Production/Kubernetes)

```yaml
# docker-compose.yml
services:
  kerberos-sidecar:
    image: platform/kerberos-sidecar:latest
    environment:
      - KRB_PRINCIPAL=svc_airflow@COMPANY.COM
      - USE_PASSWORD=false
      - KRB_KEYTAB_PATH=/krb5/keytabs/airflow.keytab
      - RENEWAL_INTERVAL=3600
    volumes:
      - ./keytabs/airflow.keytab:/krb5/keytabs/airflow.keytab:ro
```

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `KRB_PRINCIPAL` | Yes | - | Kerberos principal (user@REALM) |
| `KRB_REALM` | No | Extracted from principal | Kerberos realm |
| `USE_PASSWORD` | No | `false` | Use password instead of keytab |
| `KRB_PASSWORD` | If USE_PASSWORD=true | - | Password for authentication |
| `KRB_KEYTAB_PATH` | If USE_PASSWORD=false | `/krb5/keytabs/service.keytab` | Path to keytab file |
| `RENEWAL_INTERVAL` | No | `3600` | Seconds between renewals |
| `KRB5_CONFIG` | No | `/etc/krb5.conf` | Kerberos config file |

### Volume Mounts

| Volume | Mount Point | Purpose |
|--------|-------------|---------|
| Shared cache | `/krb5/cache` | Write tickets here (rw) |
| Keytab (if used) | `/krb5/keytabs` | Keytab file (ro) |
| krb5.conf | `/krb5/conf` or `/etc/krb5.conf` | Kerberos config (ro) |

## Testing

### Basic Tests

```bash
# Run automated tests
make test

# Expected output:
# ✓ Image exists
# ✓ Kerberos tools present
# ✓ Ticket manager executable
```

### Integration Test

```bash
# Test full ticket acquisition flow
make integration-test

# Runs sidecar for 60 seconds with test credentials
```

### Manual Testing

```bash
# Start sidecar interactively
docker run --rm -it \
  -e KRB_PRINCIPAL=test@TEST.COM \
  -e USE_PASSWORD=true \
  -e KRB_PASSWORD=testpass \
  platform/kerberos-sidecar:latest /bin/bash

# Inside container:
/scripts/kerberos-ticket-manager.sh
```

## Troubleshooting

### Sidecar won't start

```bash
# Check logs
docker logs kerberos-platform-service

# Common issues:
# - Missing KRB_PRINCIPAL environment variable
# - Keytab file not found
# - krb5.conf not accessible
```

### Tickets not renewing

```bash
# Check renewal interval
docker exec kerberos-platform-service env | grep RENEWAL

# Check ticket expiration
docker exec kerberos-platform-service klist

# Verify renewal logic in logs
docker logs kerberos-platform-service | grep "renewal"
```

### Health check failing

```bash
# Test health check manually
docker exec kerberos-platform-service klist -s
echo $?  # Should be 0

# If fails:
docker exec kerberos-platform-service klist
# Shows detailed error
```

## Architecture

```
Kerberos Sidecar Container
    ├── Obtains ticket (keytab or password)
    ├── Writes to /krb5/cache/krb5cc
    ├── Renews every RENEWAL_INTERVAL seconds
    └── Health check: klist -s
         ↓
Shared Volume (emptyDir in K8s, named volume in Docker)
         ↓
Airflow Containers (read-only)
    └── KRB5CCNAME=/krb5/cache/krb5cc
         ↓
SQL Server (Windows Authentication)
```

## Files

- **Dockerfile** - Alpine 3.19 with Kerberos + ODBC
- **scripts/kerberos-ticket-manager.sh** - Ticket lifecycle management
- **Makefile** - Build, test, push commands
- **README.md** - This file

## Corporate Registry

### Tagging for Kubernetes

```bash
# Tag for your corporate registry
make tag-for-k8s REGISTRY=registry.mycompany.com

# Push to registry
docker login registry.mycompany.com
make push REGISTRY=registry.mycompany.com
```

### Version Management

```bash
# Build with specific version tag
make build IMAGE_TAG=v1.0.0

# Tag for both latest and version
docker tag platform/kerberos-sidecar:latest platform/kerberos-sidecar:v1.0.0
```

## Security Considerations

- **Keytab files:** Mode 0600, never commit to git
- **Passwords:** Use Docker secrets, not environment variables in git
- **Ticket cache:** Shared volume, read-only for Airflow containers
- **Health checks:** Ensure tickets are valid, restart if not

## Links

- [Progressive Validation Guide](../docs/kerberos-progressive-validation.md) - Test your setup step-by-step
- [Issue #18](https://github.com/Troubladore/airflow-data-platform/issues/18) - Local development tracking
- [Issue #23](https://github.com/Troubladore/airflow-data-platform/issues/23) - Kubernetes deployment tracking
