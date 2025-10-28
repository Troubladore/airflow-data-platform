# Fix for Pagila Setup Issue with Custom Settings

## Issue Description

Corporate users reported that Pagila setup fails when using:
- Custom Docker image (corporate registry path)
- Custom repository URL
- Custom branch
- **No password (empty string)**

The container would show as "unhealthy" with the error message indicating Docker Compose failure.

## Root Cause

Through systematic debugging and TDD, we identified that **PostgreSQL Docker images require a non-empty POSTGRES_PASSWORD environment variable** to start, even when using trust authentication.

When users leave the password field empty in the wizard (or set `POSTGRES_PASSWORD=` in .env), PostgreSQL refuses to start with the error:
```
Error: Database is uninitialized and superuser password is not specified.
You must specify POSTGRES_PASSWORD to a non-empty value for the superuser.
```

## The Fix

Modified `platform-bootstrap/setup-scripts/setup-pagila.sh` to:

1. **Check for empty passwords in new .env files**: When creating a new .env, if the password is empty, automatically generate a random password.

2. **Check for empty passwords in existing .env files**: When an existing .env has an empty POSTGRES_PASSWORD, detect it and generate a random password.

The key insight is that **we maintain trust-based authentication** (configured via pg_hba.conf), so developers don't need the password to connect. The password is only required to satisfy PostgreSQL's container startup requirements.

## Technical Details

### Changes Made

**File: `platform-bootstrap/setup-scripts/setup-pagila.sh`**

Added two checks:

1. After creating new .env from template (lines 312-317):
```bash
# Also ensure password is never empty (PostgreSQL requires non-empty password)
# Check if POSTGRES_PASSWORD line exists but is empty
if grep -q "^POSTGRES_PASSWORD=$" "$PAGILA_ENV_FILE"; then
    print_warning "Empty password detected - generating random password"
    sed -i "s|^POSTGRES_PASSWORD=$|POSTGRES_PASSWORD=$RANDOM_PASSWORD|" "$PAGILA_ENV_FILE"
fi
```

2. For existing .env files (lines 339-355):
```bash
# Even if .env exists, ensure password is not empty
# PostgreSQL requires non-empty POSTGRES_PASSWORD
if grep -q "^POSTGRES_PASSWORD=$" "$PAGILA_ENV_FILE"; then
    print_warning "Empty password detected in existing .env"
    print_info "Generating random password (PostgreSQL requires non-empty password)"

    # Generate random password
    if command -v openssl >/dev/null 2>&1; then
        RANDOM_PASSWORD=$(openssl rand -base64 32)
    else
        RANDOM_PASSWORD=$(head -c 32 /dev/urandom | base64)
    fi

    # Replace empty password with random one
    sed -i "s|^POSTGRES_PASSWORD=$|POSTGRES_PASSWORD=$RANDOM_PASSWORD|" "$PAGILA_ENV_FILE"
    print_success "Password updated"
fi
```

## Verification

Created comprehensive TDD tests that verify:

1. **Empty password handling**: When POSTGRES_PASSWORD is empty, a random password is generated
2. **Container health**: After fix, containers become healthy even with initially empty passwords
3. **Corporate registry paths**: Complex registry paths like `mycorp.jfrog.io/docker-mirror/postgres:17.5-custom` work correctly
4. **Trust authentication maintained**: Developers can still connect without passwords due to pg_hba.conf

## Benefits

- ✓ Corporate users can now setup Pagila with custom images and empty passwords
- ✓ Trust-based authentication is maintained (no password needed for connections)
- ✓ Automatic password generation prevents container startup failures
- ✓ Works with complex corporate registry paths
- ✓ Backward compatible with existing setups

## Testing

Run the comprehensive test suite:
```bash
python3 test_verify_fix.py
python3 test_comprehensive_corporate.py
```

Both tests should pass, confirming the fix handles all corporate scenarios correctly.