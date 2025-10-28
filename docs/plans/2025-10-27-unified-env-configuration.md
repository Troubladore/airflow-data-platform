# Unified .env Configuration Architecture

**Date:** 2025-10-27
**Status:** Approved for Implementation
**Context:** Wizard creates platform-config.yaml but PostgreSQL startup fails due to missing .env files

## Problem Statement

The wizard successfully creates `platform-config.yaml` as the source of truth, but PostgreSQL fails to start because:
1. Makefile checks for `platform-infrastructure/.env` (exists check only)
2. Docker Compose needs `platform-bootstrap/.env` for container environment variables

This creates duplication and confusion about which file contains what.

## Design Decision

**Single Source of Truth:** `platform-config.yaml`

**Generated Artifacts:** ONE `.env` file at `platform-bootstrap/.env`

**All consumers read from this central location:**
- `platform-infrastructure/Makefile` loads via `-include ../platform-bootstrap/.env`
- `platform-infrastructure/docker-compose.yml` loads via `env_file: - ../platform-bootstrap/.env`

## Architecture

```
User runs wizard
  ↓
Wizard prompts for configuration
  ↓
Creates platform-config.yaml (source of truth)
  ↓
Generates platform-bootstrap/.env from YAML
  ↓
Both Makefile and docker-compose.yml reference same .env
  ↓
PostgreSQL starts successfully
```

## Implementation

### Change 1: Makefile (1 line)
**File:** `platform-infrastructure/Makefile`
```make
# Line ~6: Change from
-include .env

# To:
-include ../platform-bootstrap/.env
```

### Change 2: Wizard .env Generation
**File:** `wizard/services/postgres/actions.py`

**Current:**
```python
runner.write_file('platform-infrastructure/.env', env_content)
```

**New:**
```python
runner.write_file('platform-bootstrap/.env', env_content)
```

**Expand env_content to include:**
- `PLATFORM_DB_PASSWORD` (already included)
- `OPENMETADATA_DB_PASSWORD` (already included, conditionally)
- `IMAGE_POSTGRES` (already included, if non-default)
- `ENABLE_KERBEROS=true/false` (NEW - from platform-config.yaml)
- `ENABLE_OPENMETADATA=true/false` (NEW - from platform-config.yaml)
- `ENABLE_PAGILA=true/false` (NEW - from platform-config.yaml)

### Change 3: Tests
Update test file paths and assertions:
- Change assertions from `'platform-infrastructure/.env'` to `'platform-bootstrap/.env'`
- Add tests for service enable flags

## Benefits

1. **Single .env file** - No duplication
2. **Clear ownership** - Wizard generates, services consume
3. **platform-config.yaml remains source** - All .env content derives from YAML
4. **Docker Compose convention** - .env files where needed
5. **Easy to test** - One file to verify

## Effort

- Complexity: Low
- Lines changed: ~20-25
- Risk: Very low
- Time: 30-45 minutes

## Validation

After implementation:
1. Run wizard → generates platform-bootstrap/.env
2. Check file contains all required variables
3. Run `make -C platform-infrastructure start`
4. Verify PostgreSQL starts successfully
5. All tests pass
