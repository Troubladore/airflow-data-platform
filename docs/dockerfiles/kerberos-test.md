# Kerberos Test Image Dockerfile

## What Is This Image For?

The Kerberos test image validates that your platform's Kerberos ticket sharing mechanism works correctly. During the Kerberos setup wizard (Step 10/11), this container:
- Mounts the shared ticket cache from the sidecar
- Runs a Python script to verify ticket validity
- Confirms that containers can authenticate using the shared tickets

This is a critical validation step ensuring your SQL Server connections will work across all platform services.

## Technical Requirements

**Environment Variable**: `IMAGE_KERBEROS_TEST`
**Default**: Same as `IMAGE_PYTHON` (typically `python:3.11-alpine`)

### Minimum Requirements
- Python 3.11+
- Shell: `/bin/sh` or `/bin/bash`
- Volume mounting capability for `/krb5/cache`
- Package manager (layered mode) or pre-installed krb5 (prebuilt mode)

### Platform Usage
```bash
# Layered mode - installs krb5 at runtime:
docker run IMAGE_KERBEROS_TEST sh -c "apk add krb5 && python /app/test.py"

# Prebuilt mode - expects krb5 already installed:
docker run IMAGE_KERBEROS_TEST sh -c "python /app/test.py"
```

## Requirements by Mode

### Layered Mode (Default)
- **Base**: Python 3.11+ with shell access
- **Runtime**: Installs `krb5` packages on first run
- **Use Case**: Development environments, quick iteration
- **Pros**: Works with standard Python images, no pre-building needed
- **Cons**: Slower startup (package installation), requires internet access

### Prebuilt Mode
- **Base**: Python 3.11+ with `krb5` pre-installed
- **Runtime**: No package installation needed
- **Use Case**: Production, air-gapped environments, faster startup
- **Pros**: Fast validation, works offline, predictable behavior
- **Cons**: Requires custom image build and maintenance

## Alpine-Based Dockerfiles

<details>
<summary><b>Option 1: Minimal Alpine (Layered Mode)</b> - For development and testing</summary>
```dockerfile
# For use with IMAGE_MODE=layered
FROM python:3.11-alpine

# Just use the base image as-is
# Platform will install krb5 at runtime
```

**Build**: Not needed - use standard image directly
**Configure**: `IMAGE_KERBEROS_TEST=python:3.11-alpine`
**Runtime**: Platform automatically installs krb5 packages

</details>

<details>
<summary><b>Option 2: Alpine with Pre-installed Kerberos (Prebuilt Mode)</b> - For production use</summary>
```dockerfile
# For use with IMAGE_MODE=prebuilt
FROM python:3.11-alpine

# Pre-install krb5 packages
RUN apk add --no-cache \
    krb5 \
    krb5-libs \
    krb5-dev

# Add corporate CA certificates if needed
COPY corporate-ca.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Optional: Pre-configure Kerberos
COPY krb5.conf /etc/krb5.conf

# Verify installation
RUN klist -V

# Note: Must keep shell available for script execution
```

**Build**: `docker build -t myorg/kerberos-test:3.11-alpine -f Dockerfile.kerberos-test .`
**Configure**: `IMAGE_MODE=prebuilt` and `IMAGE_KERBEROS_TEST=myorg/kerberos-test:3.11-alpine`
**Versions**: Alpine 3.18+ recommended for latest krb5 packages

</details>

<details>
<summary><b>Option 3: Corporate Hardened Alpine</b> - Security-focused for enterprise</summary>
```dockerfile
# For corporate environments with security requirements
FROM python:3.11-alpine

# Install everything needed
RUN apk add --no-cache \
    krb5 \
    krb5-libs \
    krb5-dev \
    ca-certificates

# Add corporate certificates
COPY corporate-ca.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Configure Kerberos for your domain
COPY krb5.conf /etc/krb5.conf

# Create non-root user
RUN adduser -D -u 1000 -s /bin/sh testuser

# Security hardening
RUN rm -rf /var/cache/apk/* \
    && rm -rf /root/.cache \
    && find / -name "*.pyc" -delete 2>/dev/null || true

USER testuser
WORKDIR /app

# Shell must remain available for test execution
```

**Security Features**: Non-root user, minimal attack surface, cache cleanup
**Build**: `docker build -t myorg/kerberos-test:3.11-alpine-hardened -f Dockerfile.kerberos-test .`
**Note**: Requires proper krb5.conf for your Active Directory domain

</details>

## Ubuntu/Debian-Based Dockerfiles

<details>
<summary><b>Option 4: Minimal Ubuntu (Layered Mode)</b> - Standard development image</summary>
```dockerfile
# For use with IMAGE_MODE=layered
FROM python:3.11-slim-bookworm

# Base image only - krb5 installed at runtime
# Shell and apt-get must be available
```

**OS Versions**: Ubuntu 22.04 (Jammy), Debian 12 (Bookworm) recommended
**Configure**: `IMAGE_KERBEROS_TEST=python:3.11-slim-bookworm`
**Runtime**: Platform automatically installs krb5-user package

</details>

<details>
<summary><b>Option 5: Ubuntu with Pre-installed Kerberos (Prebuilt Mode)</b> - Production-ready</summary>

```dockerfile
# For organizations preferring Debian/Ubuntu
FROM python:3.11-slim-bookworm

# Install Kerberos packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        krb5-user \
        libkrb5-3 \
        libk5crypto3 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Add corporate certificates
COPY corporate-ca.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Configure Kerberos
COPY krb5.conf /etc/krb5.conf

# Verify installation
RUN klist -V
```

**Build**: `docker build -t myorg/kerberos-test:3.11-ubuntu -f Dockerfile.kerberos-test .`
**Configure**: `IMAGE_MODE=prebuilt` and `IMAGE_KERBEROS_TEST=myorg/kerberos-test:3.11-ubuntu`
**Package Notes**: `krb5-user` provides klist, kinit; `libkrb5-3` provides core libraries

</details>

## Building and Testing

### Build the Image
```bash
docker build -t myorg/kerberos-test:3.11 -f Dockerfile.kerberos-test .
```

### Test Shell Access (Required)
```bash
docker run --rm myorg/kerberos-test:3.11 sh -c "echo 'Shell works'"
```

### Test Kerberos (Prebuilt Mode)
```bash
docker run --rm myorg/kerberos-test:3.11 sh -c "klist -V"
```

### Test Kerberos (Layered Mode)
```bash
docker run --rm myorg/kerberos-test:3.11 sh -c "apk add krb5 && klist -V"
```

## Configuration

In `platform-bootstrap/.env`:

```bash
# For layered mode (default)
IMAGE_MODE=layered
IMAGE_KERBEROS_TEST=python:3.11-alpine

# For prebuilt mode
IMAGE_MODE=prebuilt
IMAGE_KERBEROS_TEST=myorg/kerberos-test:3.11
```

## Common Issues

### Issue: "sh: not found"
The image must include a shell. Even minimal images need `/bin/sh`.

### Issue: "krb5 not found" in prebuilt mode
Ensure krb5 is pre-installed when using `IMAGE_MODE=prebuilt`.

### Issue: Certificate errors
Add your corporate CA certificates to the image.

## Security Considerations

1. **Use non-root user** when possible
2. **Remove package managers** after installation (if not needed)
3. **Clear caches** to reduce image size
4. **Scan for vulnerabilities** before deployment

## Notes

- The test script (`test_kerberos_simple.py`) is mounted at runtime
- The Kerberos ticket cache is mounted as `/krb5/cache`
- Environment variable `KRB5CCNAME` is set to `/krb5/cache/krb5cc`
- The container must be able to join the `platform_network`