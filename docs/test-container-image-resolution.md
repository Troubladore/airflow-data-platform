# Test Container Image Resolution - Bug Fix

## Problem

Users reported that test container validation fails with:
```
Prerequisites  [FAIL] postgres-test container running
```

Even when they configured a custom test image like `custom/postgres-conn`, the system was checking for a hard-coded `postgres-test` container name.

## Root Cause

Test container verification code was using hard-coded image names (`platform/postgres-test:latest`, `platform/pagila-test:latest`) instead of reading the configured image from the context or configuration files.

This occurs in two places:
1. **Base Platform (postgres)**: Verification scripts checking for `postgres-test` container
2. **Pagila**: `verify_pagila_connection` action hard-coding `platform/pagila-test:latest`

## Solution

### Pagila Fix (Implemented)

Updated `wizard/services/pagila/actions.py` - `verify_pagila_connection()`:
- Now reads test image from context: `ctx.get('services.pagila.test_containers.pagila_test.image')`
- Respects prebuilt vs build-from-base mode
- Uses configured image name instead of hard-coded `platform/pagila-test:latest`

### Base Platform Fix (Needed)

The same pattern needs to be applied to base_platform postgres verification.

**Files that likely need updates:**
1. Any script checking for "postgres-test container running"
2. Verification/validation scripts in `platform-bootstrap/tests/`
3. Setup scripts that validate prerequisites

**Fix Pattern:**
```bash
# BEFORE (hard-coded):
if docker ps | grep -q "postgres-test"; then
    print_check "PASS" "postgres-test container running"
fi

# AFTER (use configuration):
TEST_IMAGE=$(grep "IMAGE_POSTGRES_TEST=" .env | cut -d= -f2)
if docker images | grep -q "$TEST_IMAGE\|platform/postgres-test"; then
    print_check "PASS" "postgres test container available"
fi
```

## How Images Should Work

### Build Mode (PREBUILT=false)
1. User configures base image: `alpine:latest` or `mycompany/alpine:3.19`
2. Build process: `docker build --build-arg BASE_IMAGE=<configured> -t platform/postgres-test:latest`
3. Verification uses: `platform/postgres-test:latest` (standard tag after build)

### Prebuilt Mode (PREBUILT=true)
1. User configures complete image: `mycompany.jfrog.io/postgres-test:2025.1`
2. Build process: `docker pull <configured> && docker tag <configured> platform/postgres-test:latest`
3. Verification uses: `platform/postgres-test:latest` (standard tag after pull/tag)

**Key Point**: The build process should ALWAYS tag to `platform/{service}-test:latest` for consistency, but it should pull/build from the CONFIGURED image.

## Testing

### Test with Default Images
```bash
# Should work with alpine:latest
IMAGE_POSTGRES_TEST=alpine:latest
POSTGRES_TEST_PREBUILT=false
```

### Test with Custom Base
```bash
# Should work with custom base
IMAGE_POSTGRES_TEST=mycompany/alpine:3.19-hardened
POSTGRES_TEST_PREBUILT=false
```

### Test with Prebuilt Corporate Image
```bash
# Should work with prebuilt corporate image
IMAGE_POSTGRES_TEST=artifactory.company.com/postgres-test:2025.1
POSTGRES_TEST_PREBUILT=true
```

## Related Files

- `wizard/services/pagila/actions.py` - ✅ Fixed
- `wizard/services/base_platform/actions.py` - ⚠️  Needs review
- `platform-bootstrap/tests/*.sh` - ⚠️  May need updates
- `platform-infrastructure/Makefile` - ✅ Already uses env vars correctly

## User Impact

Without this fix:
- Users with custom/corporate images see confusing "postgres-test container running" errors
- Test container verification fails even when correct image is configured
- No way to use corporate-approved test images

With this fix:
- Test container verification works with any configured image
- Prebuilt mode works correctly with corporate registries
- Error messages reference actual configured image, not hard-coded name
