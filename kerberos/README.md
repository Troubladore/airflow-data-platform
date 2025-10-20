# Kerberos Sidecar - Standalone Ticket Sharing Service

Shares Kerberos tickets from your host machine with Docker containers for SQL Server authentication.

## Overview

The Kerberos sidecar:
- **Copies tickets** from your host machine (no KDC needed!)
- **Shares tickets** with other containers via volume mount
- **Auto-refreshes** tickets every 5 minutes
- **Zero configuration** for local development

## Quick Start

```bash
# 1. Get a Kerberos ticket on your host
kinit YOUR_USERNAME@COMPANY.COM

# 2. Configure
cp .env.example .env
# Edit COMPANY_DOMAIN in .env

# 3. Build the sidecar image (one-time)
make build

# 4. Start
make start

# 5. Verify
make status
make test
```

## How It Works

```
Host Machine           Docker Container
┌──────────────┐      ┌──────────────────┐
│ kinit        │      │                  │
│ klist        │──┐   │  Airflow DAG     │
│              │  │   │  uses ticket     │
│ ~/.krb5-cache│  │   │  ↓               │
└──────────────┘  │   │  SQL Server      │
                  │   │  connection      │
                  │   │  (Windows auth)  │
                  └──→│  /krb5/cache/    │
                      └──────────────────┘
```

**Benefits:**
- Use your existing corporate Kerberos
- No password in .env (copies your kinit ticket)
- Works with Windows domain / Active Directory
- No KDC installation needed

## Architecture

**Service:**
- `kerberos-sidecar` - Ticket copy/refresh service

**Volumes:**
- `platform_kerberos_cache` - Shared ticket cache (other services mount this read-only)

**Standalone:** No external dependencies. Other services optionally mount the ticket volume.

## Usage

```bash
make build     # Build sidecar image
make start     # Start Kerberos sidecar
make stop      # Stop Kerberos sidecar
make status    # Check service health
make test      # Test ticket availability
make logs      # View service logs
make clean     # Remove (WARNING: deletes ticket cache!)
```

## Configuration

See `.env.example` for all configuration options:
- `COMPANY_DOMAIN` - Your Active Directory domain
- `KERBEROS_TICKET_DIR` - Where host tickets are stored
- `TICKET_MODE` - copy (local dev) or create (production)
- `KRB5_CONF_PATH` - Path to krb5.conf

## Using with Other Services

Other containers can access Kerberos tickets by:

1. **Mounting the volume:**
   ```yaml
   volumes:
     - platform_kerberos_cache:/krb5/cache:ro
   ```

2. **Setting environment:**
   ```yaml
   environment:
     KRB5CCNAME: /krb5/cache/krb5cc
     KRB5_CONFIG: /etc/krb5.conf
   ```

See OpenMetadata or Airflow examples for integration patterns.

## Troubleshooting

**No ticket found:**
```bash
# On host machine
kinit YOUR_USERNAME@COMPANY.COM
klist  # Verify ticket exists

# Check sidecar can see it
make test
```

**Ticket not refreshing:**
```bash
make logs      # Check for copy errors
make restart   # Restart sidecar
```
