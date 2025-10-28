# Custom Image Validation Test Suite

This test suite addresses all concerns from [Issue #98](https://github.com/Troubladore/airflow-data-platform/issues/98) regarding auth-restricted prebuilt image scenarios and ensures the platform correctly handles enterprise Docker registry configurations.

## Test Suite Components

### 1. Core Validation Tests

#### `test-custom-image-validation.sh`
Comprehensive validation of custom image handling across all scenarios:
- **PostgreSQL Custom Image Persistence**: Verifies custom images persist across wizard runs
- **Auth-Restricted Prebuilt Mode**: Tests prebuilt images with authentication requirements
- **Complex Registry Paths**: Validates handling of registries with port numbers
- **Multi-Service Custom Images**: Tests multiple services with custom images
- **Edge Cases**: Mode switching, invalid names, missing dependencies

**Run:** `./tests/test-custom-image-validation.sh`

### 2. Integration Tests

#### `test-platform-integration.sh`
End-to-end testing of platform setup with custom images:
- Simulates actual platform setup flow
- Tests configuration persistence and reload
- Validates environment variable generation
- Verifies docker-compose integration

**Run:** `./tests/test-platform-integration.sh`

### 3. Clean-Slate Tests

#### `test-clean-slate-images.sh`
Verifies proper cleanup of custom images:
- Tests image tracking mechanisms
- Validates complete removal of custom images
- Ensures configuration cleanup
- Verifies no artifacts remain

**Run:** `./tests/test-clean-slate-images.sh`

### 4. Service-Specific Tests

#### `test-all-custom-images.sh`
Tests custom image propagation to all services:
- Pagila (bash script receives IMAGE_POSTGRES)
- Platform-Infrastructure (docker-compose reads .env)
- OpenMetadata (custom server and OpenSearch images)
- Kerberos (prebuilt mode with custom images)

**Run:** `./tests/test-all-custom-images.sh`

## Test Image Setup

### Prerequisites

1. Docker must be installed and running
2. Python 3.x with PyYAML module
3. The `mock-corporate-image.py` utility

### Creating Test Images

```bash
# Create all test images defined in test-images.yaml
./mock-corporate-image.py test-setup

# Check status of test images
./mock-corporate-image.py test-status

# Remove all test images when done
./mock-corporate-image.py test-teardown
```

## Test Images Configuration

Test images are defined in `test-images.yaml` and include:

### Standard Images (Tagged)
- **PostgreSQL Corporate**: `mycorp.jfrog.io/docker-mirror/mycorp-approved-images/postgres/17.5:2025.10.01`
- **PostgreSQL with Port**: `internal.artifactory.company.com:8443/docker-prod/postgres/17.5:v2025.10-hardened`
- **OpenMetadata Server**: `artifactory.corp.net/docker-public/openmetadata/server:1.5.11-approved`
- **OpenSearch**: `docker-registry.internal.company.com/data/opensearch:2.18.0-enterprise`

### Prebuilt Images (Built with packages)
- **Kerberos Ubuntu**: `mycorp.jfrog.io/platform/kerberos-sidecar:ubuntu-22.04-prebuilt`
- **Kerberos Debian**: `company.registry.io:5000/security/kerberos/debian:12-slim-krb5-v1.20`
- **Kerberos Base**: `mycorp.jfrog.io/docker-mirror/mycorp-approved-images/kerberos-base:latest`
- **SQL Auth Base**: `mycorp.jfrog.io/docker-mirror/mycorp-approved-images/sql-auth-base:latest`

### Auth-Restricted Base
- **Wolfi Base**: `mycorp.jfrog.io/docker-mirror/mycorp-approved-images/wolfi-base:latest`

## Running All Tests

### Quick Test
```bash
# Run basic validation tests
./tests/test-custom-image-validation.sh
```

### Full Test Suite
```bash
# Setup test images
./mock-corporate-image.py test-setup

# Run all tests
./tests/test-custom-image-validation.sh
./tests/test-platform-integration.sh
./tests/test-clean-slate-images.sh
./tests/test-all-custom-images.sh

# Cleanup
./mock-corporate-image.py test-teardown
```

### Continuous Integration
```bash
# CI-friendly test with setup and teardown
./mock-corporate-image.py test-setup && \
  ./tests/test-custom-image-validation.sh && \
  ./tests/test-platform-integration.sh && \
  ./tests/test-clean-slate-images.sh && \
  ./mock-corporate-image.py test-teardown
```

## Test Scenarios Covered

### ✅ Scenario 1: PostgreSQL Custom Image Persistence
- Custom image saved in platform-bootstrap/.env
- Wizard remembers image on subsequent runs
- Clean-slate removes the custom image

### ✅ Scenario 2: Auth-Restricted Prebuilt Mode
- Prebuilt images accepted by installer
- No attempt to pull base images at runtime
- Kerberos and SQL tools work correctly

### ✅ Scenario 3: Complex Registry Paths with Ports
- Registry URLs with ports (e.g., :8443) handled correctly
- Image pulled/used without parsing errors
- Clean-slate removes properly

### ✅ Scenario 4: Multi-Service Custom Images
- All custom images saved to configuration
- All remembered on re-run
- All removed during clean-slate

### ✅ Edge Cases
- **Mode Switching**: Layered to prebuilt mode transitions
- **Invalid Images**: Proper error handling for malformed names
- **Missing Dependencies**: Graceful handling of incomplete prebuilt images

## Success Criteria

All tests must pass for the platform to be considered ready for enterprise deployment:

- ✅ All 4 main scenarios pass
- ✅ Edge cases handled appropriately
- ✅ No crashes or unhandled exceptions
- ✅ Configuration persists correctly
- ✅ Clean-slate truly cleans everything
- ✅ Prebuilt mode doesn't attempt runtime installation

## Formatting and Style

All test scripts use the platform's formatting library (`platform-bootstrap/lib/formatting.sh`) for consistent output. This ensures:
- Proper color support with NO_COLOR environment variable handling
- Consistent status indicators (✓, ✗, ⚠, ℹ)
- Professional, unified appearance across all tests

## Troubleshooting

### Test Images Not Found
```bash
# Check if images exist
./mock-corporate-image.py test-status

# Recreate if needed
./mock-corporate-image.py test-setup
```

### Permission Denied
```bash
# Make scripts executable
chmod +x tests/*.sh
chmod +x mock-corporate-image.py
```

### Docker Issues
```bash
# Ensure Docker is running
docker ps

# Clean up any stale containers/images
docker system prune -a
```

## Contributing

When adding new tests:
1. Use the platform formatting library
2. Follow existing naming conventions
3. Include comprehensive documentation
4. Update this README with test descriptions
5. Ensure tests are idempotent (can run multiple times)
6. Exit with proper status codes (0 for success, 1 for failure)

## Related Documentation

- [Issue #98: Test auth-restricted prebuilt image scenarios](https://github.com/Troubladore/airflow-data-platform/issues/98)
- [Mock Corporate Image Utility](../mock-corporate-image.py)
- [Test Images Configuration](../test-images.yaml)
- [Platform Bootstrap Documentation](../platform-bootstrap/README.md)