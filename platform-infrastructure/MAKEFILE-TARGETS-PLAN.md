# Makefile Targets Plan for Test Containers

## Overview

This document outlines the Makefile targets that need to be added to support building test containers for both build-from-base and prebuilt modes. These targets will be added to the `platform-infrastructure/Makefile` to align with the existing build patterns used in the platform.

## Required Makefile Targets

### 1. `build-postgres-test`
Builds the PostgreSQL test container with Kerberos/GSSAPI support.

### 2. `build-sqlcmd-test`
Builds the SQL Server test container with FreeTDS/sqlcmd and Kerberos support.

### 3. `build-test-containers`
Meta-target that builds both test containers.

## Target Logic

### Prebuilt Mode (POSTGRES_TEST_PREBUILT=true)
- Pull the prebuilt image specified in `IMAGE_POSTGRES_TEST`
- Tag it as `platform/postgres-test:latest`

### Build Mode (POSTGRES_TEST_PREBUILT=false)
- Build from the base image specified in `IMAGE_POSTGRES_TEST`
- Use `--build-arg BASE_IMAGE` to specify the base image
- Tag the result as `platform/postgres-test:latest`

The same logic applies to `sqlcmd-test` container with `SQLCMD_TEST_PREBUILT` and `IMAGE_SQLCMD_TEST` variables.

## Implementation Details

### Environment Variables
The following variables are defined in `platform-bootstrap/.env`:
- `IMAGE_POSTGRES_TEST` - Base image or prebuilt image for postgres-test
- `POSTGRES_TEST_PREBUILT` - Boolean flag for build vs prebuilt mode
- `IMAGE_SQLCMD_TEST` - Base image or prebuilt image for sqlcmd-test
- `SQLCMD_TEST_PREBUILT` - Boolean flag for build vs prebuilt mode

### Build Context
Both containers are located in:
- `platform-infrastructure/test-containers/postgres-test/`
- `platform-infrastructure/test-containers/sqlcmd-test/`

## Example Commands

### Build Mode Examples
```bash
# Build postgres-test from base image
docker build \
  --build-arg BASE_IMAGE=alpine:latest \
  -t platform/postgres-test:latest \
  platform-infrastructure/test-containers/postgres-test/

# Build sqlcmd-test from base image
docker build \
  --build-arg BASE_IMAGE=alpine:latest \
  -t platform/sqlcmd-test:latest \
  platform-infrastructure/test-containers/sqlcmd-test/
```

### Prebuilt Mode Examples
```bash
# Pull and retag postgres-test prebuilt image
docker pull artifactory.company.com/docker-local/platform/postgres-test:2025.1
docker tag artifactory.company.com/docker-local/platform/postgres-test:2025.1 platform/postgres-test:latest

# Pull and retag sqlcmd-test prebuilt image
docker pull artifactory.company.com/docker-local/platform/sqlcmd-test:2025.1
docker tag artifactory.company.com/docker-local/platform/sqlcmd-test:2025.1 platform/sqlcmd-test:latest
```

## Integration with Existing Makefile Structure

The new targets should follow the same pattern as existing targets in the platform:

1. **Help Integration**: Add descriptions to the help target
2. **Environment Loading**: Include `-include ../platform-bootstrap/.env` to load configuration
3. **Docker Compose Integration**: Work with existing docker-compose.yml if applicable
4. **Dependency Management**: `build-test-containers` should depend on both individual build targets

## Target Dependencies

```
build-test-containers
├── build-postgres-test
└── build-sqlcmd-test
```

## Usage Examples

```bash
# Build both test containers
make build-test-containers

# Build only postgres-test container
make build-postgres-test

# Build only sqlcmd-test container
make build-sqlcmd-test
```

## Error Handling

The targets should include appropriate error handling:
- Check if required environment variables are set
- Validate that Docker is available
- Provide clear error messages for missing configuration
- Handle both build and prebuilt modes appropriately

## Security Considerations

- Both containers should run as non-root users (testuser, uid 10001)
- Follow least privilege principles
- No hardcoded credentials or secrets in images
- Proper image tagging and validation