# Test Images Documentation

## Overview

This document describes the test image system used to validate the platform installer's ability to handle complex corporate Docker registry naming conventions. The system ensures we can always recreate and test with the exact same complex image paths that customers use in enterprise environments.

## Quick Start

```bash
# Check what test images exist
./mock-corporate-image.py test-status

# Create all test images
./mock-corporate-image.py test-setup

# Remove all test images
./mock-corporate-image.py test-teardown
```

## Test Image Configuration

All test images are defined in `test-images.yaml`. This file is version-controlled and contains:
- The exact complex registry paths to test
- Source images to use
- Build instructions for prebuilt images
- Test scenarios and validation steps

## Key Test Cases

### 1. Complex PostgreSQL Corporate Image
**Image**: `mycorp.jfrog.io/docker-mirror/mycorp-approved-images/postgres/17.5:2025.10.01`

This is our primary test case that simulates:
- Deep registry path with multiple segments
- Corporate mirror structure (`docker-mirror/mycorp-approved-images`)
- Date-based versioning (2025.10.01)
- JFrog Artifactory registry naming

**Testing Steps**:
1. Create the mock image: `./mock-corporate-image.py test-setup`
2. Run the platform installer: `./platform setup`
3. When prompted for PostgreSQL image, enter the full corporate path
4. Verify it's saved in `platform-bootstrap/.env`
5. Re-run setup to verify persistence
6. Run `./platform clean-slate` to verify removal

### 2. PostgreSQL with Port Number
**Image**: `internal.artifactory.company.com:8443/docker-prod/postgres/17.5:v2025.10-hardened`

Tests handling of:
- Registry URLs with explicit port numbers
- "Hardened" image tags
- Internal company domains

### 3. Prebuilt Kerberos Images
**Ubuntu**: `mycorp.jfrog.io/platform/kerberos-sidecar:ubuntu-22.04-prebuilt`
**Debian**: `company.registry.io:5000/security/kerberos/debian:12-slim-krb5-v1.20`

These test:
- Prebuilt images with packages already installed
- Different base operating systems
- Security-specific registry paths

## How It Works

### Persistence
The `test-images.yaml` file ensures we always have the exact same test configuration:
- Committed to version control
- Can be modified to add new test cases
- Readable by both the mock utility and me (Claude) for consistent recreation

### Recreation Process
When you need to recreate test images (e.g., after Docker cleanup):
```bash
./mock-corporate-image.py test-setup
```

This command:
1. Reads `test-images.yaml`
2. Creates each mock image with the exact specified name
3. For simple images: tags existing Docker images
4. For Kerberos: builds images with required packages

### Verification
Always verify test images before testing:
```bash
./mock-corporate-image.py test-status
```

This shows:
- Which test images exist
- Which are missing
- Image sizes
- Quick visual status

## Adding New Test Cases

To add a new test case:

1. Edit `test-images.yaml`
2. Add a new entry under `test_images`:
```yaml
  new_test_case:
    description: "What this tests"
    type: "tag"  # or "build-kerberos"
    source_image: "base:image"
    mock_name: "complex.registry.path/image:tag"
    use_case: "Why we need this test"
```

3. Run `./mock-corporate-image.py test-setup` to create it

## Common Test Scenarios

### Before Shipping Features
Always run these tests before shipping:

```bash
# 1. Setup test images
./mock-corporate-image.py test-setup

# 2. Test PostgreSQL custom image persistence
./platform setup
# Use: mycorp.jfrog.io/docker-mirror/mycorp-approved-images/postgres/17.5:2025.10.01

# 3. Verify it persists
./platform setup  # Should remember the custom image

# 4. Test clean-slate removal
./platform clean-slate  # Should remove the custom image

# 5. Test with Kerberos prebuilt
./platform setup
# Enable Kerberos
# Use: mycorp.jfrog.io/platform/kerberos-sidecar:ubuntu-22.04-prebuilt
# Select "prebuilt" mode

# 6. Clean up
./platform clean-slate
./mock-corporate-image.py test-teardown
```

## Troubleshooting

### Test images missing after Docker cleanup
Simply recreate them:
```bash
./mock-corporate-image.py test-setup
```

### Need to verify what's configured
Check the configuration:
```bash
cat test-images.yaml
```

### Image creation fails
Check Docker is running and you have the base images:
```bash
docker pull postgres:17.5-alpine
docker pull ubuntu:22.04
docker pull debian:12-slim
```

## For Claude

When working on platform installer features, I can always:
1. Read `test-images.yaml` to see exact test configurations
2. Use `./mock-corporate-image.py test-setup` to recreate test images
3. Reference the complex PostgreSQL path: `mycorp.jfrog.io/docker-mirror/mycorp-approved-images/postgres/17.5:2025.10.01`
4. Test with this exact configuration before any changes are shipped

The test configuration is persistent and version-controlled, ensuring consistent testing across sessions.