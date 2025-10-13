# Kerberos Quick Start Guide

One-page reference for the Kerberos Setup Wizard

## First-Time Setup (10 minutes)

```bash
cd airflow-data-platform/platform-bootstrap
make kerberos-setup
```

Follow the wizard through 10 guided steps. That's it!

## Daily Usage

```bash
# Morning - Get Kerberos ticket
kinit your.username@COMPANY.COM

# Start platform services
make platform-start

# Your Airflow projects now have Kerberos authentication!

# Evening - Stop services
make platform-stop
```

## Common Commands

```bash
# Setup & Configuration
make kerberos-setup          # Interactive setup wizard (first time)
make kerberos-diagnose       # Troubleshoot issues

# Service Management
make platform-start          # Start all services
make platform-stop           # Stop all services
make platform-status         # Check status

# Testing
make test-kerberos-simple    # Test ticket sharing (30 seconds)
make test-kerberos-full      # Test SQL Server (interactive)

# Ticket Management
klist                        # Check ticket status
kinit user@DOMAIN.COM        # Get new ticket
kdestroy                     # Remove all tickets
```

## Troubleshooting Quick Fixes

### No Kerberos Ticket
```bash
# Get a ticket
kinit your.username@COMPANY.COM

# Verify
klist
```

### Ticket Not Shared with Containers
```bash
# Run diagnostic
make kerberos-diagnose

# Reconfigure if needed
make kerberos-setup
```

### Services Won't Start
```bash
# Check Docker
docker info

# Fix network
make fix-network

# Rebuild
cd kerberos-sidecar && make build
```

### SQL Server Connection Fails
```bash
# Check ticket
klist

# Test basic sharing
make test-kerberos-simple

# If basic test passes, check:
# 1. Server name correct?
# 2. On VPN?
# 3. Have database access?
```

## Configuration Quick Reference

Your `.env` file should contain:

```bash
# Detected automatically by wizard
COMPANY_DOMAIN=COMPANY.COM
KERBEROS_CACHE_TYPE=FILE              # or DIR
KERBEROS_CACHE_PATH=/tmp              # or ${HOME}/.krb5-cache
KERBEROS_CACHE_TICKET=krb5cc_1000     # or dev/tkt
```

## File Locations

```
platform-bootstrap/
├── setup-kerberos.sh              # Setup wizard
├── diagnose-kerberos.sh           # Diagnostic tool
├── test-kerberos.sh               # SQL Server test
├── .env                           # Your configuration
├── docker-compose.yml             # Service definitions
└── kerberos-sidecar/              # Sidecar build
```

## Getting Help

```bash
# Wizard help
./setup-kerberos.sh --help

# Resume interrupted setup
./setup-kerberos.sh --resume

# Start fresh
./setup-kerberos.sh --reset
```

## What Each Step Does

1. **Prerequisites** - Checks Docker, krb5-user
2. **krb5.conf** - Validates Kerberos configuration
3. **KDC Test** - Checks network connectivity
4. **Get Ticket** - Helps obtain Kerberos ticket
5. **Detect Location** - Auto-finds ticket cache
6. **Update .env** - Configures environment
7. **Build Sidecar** - Creates Docker image
8. **Start Services** - Brings up containers
9. **Test Sharing** - Verifies ticket access
10. **Test SQL** - Optional database test

## Expected Timeline

- **First-time setup**: 10-15 minutes
- **Daily startup**: 30 seconds
- **Ticket renewal**: 10 seconds (kinit)
- **Troubleshooting**: 5 minutes with wizard

## Success Indicators

You'll know it's working when:
- ✓ `klist` shows valid ticket
- ✓ `make test-kerberos-simple` passes
- ✓ `docker compose ps` shows services running
- ✓ Your Airflow DAGs can query SQL Server

## Further Documentation

- **Complete Guide**: [KERBEROS-SETUP-WIZARD.md](./KERBEROS-SETUP-WIZARD.md)
- **Getting Started**: [../docs/getting-started-simple.md](../docs/getting-started-simple.md)
- **Diagnostic Guide**: [../docs/kerberos-diagnostic-guide.md](../docs/kerberos-diagnostic-guide.md)
- **WSL2 Setup**: [../docs/kerberos-setup-wsl2.md](../docs/kerberos-setup-wsl2.md)

---

**Need help?** Run `make kerberos-setup` - the wizard guides you through everything!
