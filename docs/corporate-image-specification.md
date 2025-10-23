# Corporate Image Flexibility Specification

## Overview

Enable the platform to work with highly restricted corporate Docker images that:
- Don't include bash/sh shells
- Prohibit runtime package installation
- Are pre-built with all required dependencies
- Follow strict security baselines

## Design Principles

1. **Separation of Concerns**: Different images for different purposes
2. **Zero Assumptions**: Don't assume shell access or package managers
3. **Pre-built Ready**: Support images that are complete and locked down
4. **Backward Compatible**: Default behavior unchanged

## Proposed Solution

### 1. Image Usage Modes

Add a new environment variable `IMAGE_MODE` with two values:

- `layered` (default): Current behavior - builds upon base images
- `prebuilt`: Use images as-is, no runtime modifications

```bash
# In platform-bootstrap/.env
IMAGE_MODE=prebuilt  # Use corporate pre-built images
```

### 2. Separate Image Variables

Split image variables by purpose:

| Variable | Purpose | Default | Prebuilt Requirement |
|----------|---------|---------|---------------------|
| `IMAGE_PYTHON` | Python runtime for DAGs | `python:3.11-alpine` | Python 3.11+ |
| `IMAGE_KERBEROS_TEST` | Kerberos validation | `python:3.11-alpine` | Python + krb5 + test script |
| `IMAGE_POSTGRES` | PostgreSQL database | `postgres:17.5-alpine` | PostgreSQL 17.5+ |
| `IMAGE_OPENMETADATA_SERVER` | OpenMetadata server | `docker.getcollate.io/openmetadata/server:1.10.1` | OpenMetadata 1.10.1 |
| `IMAGE_OPENSEARCH` | OpenSearch engine | `opensearchproject/opensearch:2.19.2` | OpenSearch 2.19.2 |

### 3. Conditional Logic

#### In Kerberos setup.sh:

```bash
if [ "$IMAGE_MODE" = "prebuilt" ]; then
    # Use pre-built image directly, no package installation
    test_image="${IMAGE_KERBEROS_TEST:-myorg/kerberos-test:latest}"
    docker run --rm \
        --network platform_network \
        -v platform_kerberos_cache:/krb5/cache:ro \
        "$test_image" \
        # No shell command, image entrypoint handles everything
else
    # Current layered approach
    test_image="${IMAGE_PYTHON:-python:3.11-alpine}"
    docker run --rm \
        --network platform_network \
        -v platform_kerberos_cache:/krb5/cache:ro \
        "$test_image" \
        sh -c "apk add krb5 && python /app/test.py"
fi
```

## Implementation Plan

### Phase 1: Core Changes

1. **Update platform-bootstrap/.env.example**
   - Add `IMAGE_MODE` variable
   - Add `IMAGE_KERBEROS_TEST` variable
   - Document both modes

2. **Modify kerberos/setup.sh**
   - Check `IMAGE_MODE`
   - Use appropriate image and command based on mode
   - Handle missing shell gracefully

3. **Create sample Dockerfiles**
   - `/docs/dockerfiles/kerberos-test/Dockerfile`
   - `/docs/dockerfiles/python-runner/Dockerfile`
   - `/docs/dockerfiles/postgres-custom/Dockerfile`

### Phase 2: Documentation

1. **Corporate Image Guide** (`/docs/corporate-images.md`)
   - How to build compliant images
   - Required capabilities per image type
   - Testing procedures

2. **Migration Guide** (`/docs/migration-to-prebuilt.md`)
   - Converting from layered to prebuilt
   - Common issues and solutions

## Sample Dockerfiles

### Kerberos Test Image (Prebuilt)

```dockerfile
# docs/dockerfiles/kerberos-test/Dockerfile
FROM python:3.11-alpine AS builder

# Install all dependencies at build time
RUN apk add --no-cache krb5 krb5-libs

# Copy test script
COPY test_kerberos.py /app/test.py

# Create non-root user
RUN adduser -D -u 1000 testuser

# Set up entrypoint (no shell required)
USER testuser
WORKDIR /app
ENV KRB5CCNAME=/krb5/cache/krb5cc

# Direct Python execution, no shell
ENTRYPOINT ["python", "/app/test.py"]
```

### Python Runner Image (Prebuilt)

```dockerfile
# docs/dockerfiles/python-runner/Dockerfile
FROM python:3.11-slim

# Corporate requirements
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        krb5-user \
        libpq-dev \
        && rm -rf /var/lib/apt/lists/*

# Add corporate CA certificates
COPY corporate-ca.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Install Python packages
COPY requirements.txt /tmp/
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Security: Remove package managers
RUN apt-get purge -y --auto-remove apt && \
    rm -rf /var/lib/dpkg /var/cache/apt

# No shell, direct Python
ENTRYPOINT ["python"]
```

## Configuration Examples

### Layered Mode (Default)
```bash
# platform-bootstrap/.env
IMAGE_MODE=layered
IMAGE_PYTHON=python:3.11-alpine
# Kerberos test uses IMAGE_PYTHON with runtime package installation
```

### Prebuilt Mode (Corporate)
```bash
# platform-bootstrap/.env
IMAGE_MODE=prebuilt
IMAGE_PYTHON=myorg/python-runner:3.11-secure
IMAGE_KERBEROS_TEST=myorg/kerberos-test:3.11-secure
IMAGE_POSTGRES=myorg/postgres:17.5-hardened
# All images are complete, no runtime modifications
```

## Testing Strategy

1. **Layered Mode Tests** (maintain current tests)
   - Default images work
   - Runtime package installation succeeds

2. **Prebuilt Mode Tests** (new)
   - Images work without shell access
   - No runtime package installation attempted
   - All required capabilities present

## Benefits

1. **Security**: Support locked-down corporate images
2. **Flexibility**: Choose between convenience and security
3. **Compatibility**: Works with distroless and minimal images
4. **Performance**: Prebuilt images start faster (no setup)

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Complexity increase | Clear documentation and examples |
| Breaking changes | Default mode unchanged |
| Image size | Document optimization techniques |
| Debugging difficulty | Provide debug variants with shells |

## Success Criteria

- [ ] Platform works with distroless images in prebuilt mode
- [ ] No shell commands executed in prebuilt mode
- [ ] Default layered mode unchanged
- [ ] Clear documentation for both modes
- [ ] Sample Dockerfiles for all image types