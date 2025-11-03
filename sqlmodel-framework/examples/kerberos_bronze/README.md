# Kerberos Bronze Example

This example demonstrates how to use the SQLModel Framework with Kerberos authentication for enterprise PostgreSQL databases.

## What This Example Shows

- ✅ Kerberos/GSSAPI authentication without passwords
- ✅ Automatic username extraction from Kerberos ticket
- ✅ Handling container authentication issues (root user)
- ✅ Secure connection with GSSAPI encryption
- ✅ Bronze layer extraction with enterprise auth

## Prerequisites

### 1. Kerberos Environment

You need a working Kerberos environment:
- KDC (Key Distribution Center) accessible
- Valid Kerberos ticket (`kinit` completed)
- PostgreSQL server configured for GSSAPI

### 2. Verify Kerberos Setup

```bash
# Check if you have a valid ticket
klist

# Output should show:
# Ticket cache: FILE:/tmp/krb5cc_1000
# Default principal: username@REALM.COM
#
# Valid starting     Expires            Service principal
# 01/15/24 08:00:00  01/15/24 18:00:00  krbtgt/REALM.COM@REALM.COM
```

### 3. PostgreSQL Server Requirements

The PostgreSQL server must be configured for Kerberos:
- `pg_hba.conf` with GSSAPI authentication
- Kerberos service principal (e.g., `postgres/hostname@REALM`)
- Proper DNS resolution

## Running the Example

### Setup

```bash
# Install dependencies
uv sync

# Get Kerberos ticket (if not already)
kinit username@REALM.COM

# Set environment variables
export DB_HOST=pgserver.example.com
export DB_NAME=analytics
```

### Run

```bash
python extract_with_kerberos.py
```

This will:
1. Connect using Kerberos (no password needed!)
2. Extract data from specified tables
3. Add Bronze metadata
4. Write to Bronze storage

## Key Concepts

### 1. Kerberos Configuration

The framework handles all Kerberos complexity:

```python
config = PostgresConfig(
    host="pgserver.example.com",
    database="analytics",
    use_kerberos=True,        # Enable Kerberos
    gssencmode="require"      # Require encrypted connection
)
```

### 2. No Passwords Needed

With Kerberos, you don't need passwords in code:
```python
# ❌ Don't do this (security risk)
config = PostgresConfig(
    host="...",
    username="user",
    password="SecretPassword123!"  # Bad!
)

# ✅ Do this (secure)
config = PostgresConfig(
    host="...",
    use_kerberos=True  # Uses ticket, no password!
)
```

### 3. Container Authentication

The framework handles the container root user issue:

```python
# Framework automatically detects and handles:
# - Running as root in container (UID 0)
# - Kerberos ticket ownership issues
# - Username extraction from ticket
```

## Troubleshooting

### Debug Kerberos

```python
# Enable Kerberos trace
import os
os.environ["KRB5_TRACE"] = "/dev/stderr"

# Run your script to see detailed Kerberos operations
```

### Common Issues

1. **"No credentials cache found"**
   - Run `kinit username@REALM.COM`

2. **"Server not found in Kerberos database"**
   - Check DNS resolution
   - Verify server has Kerberos principal

3. **"GSSAPI authentication failed"**
   - Check `pg_hba.conf` on server
   - Verify realm configuration

4. **Container permission issues**
   - Framework should handle automatically
   - Check ticket is readable by container user

## Security Best Practices

1. **Never commit passwords** - Use Kerberos instead
2. **Use gssencmode="require"** - Enforce encrypted connections
3. **Rotate tickets regularly** - Use `kinit -R` for renewal
4. **Monitor ticket expiry** - Set up alerts for expiring tickets

## Files in This Example

- `extract_with_kerberos.py` - Main extraction with Kerberos
- `models.py` - Bronze table definitions
- `pyproject.toml` - Dependencies
- `README.md` - This file

## Next Steps

1. Set up Kerberos in your environment
2. Configure PostgreSQL for GSSAPI
3. Use this pattern for production Bronze pipelines
4. Check the [API Reference](../../API_REFERENCE.md) for more options