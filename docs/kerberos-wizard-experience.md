# Kerberos Wizard Experience Guide

This guide explains what to expect when running the Kerberos setup wizard and how it helps you configure authentication for your data platform.

## 🎯 Overview

The Kerberos wizard (`./dev-tools/setup-kerberos.sh`) provides an interactive, guided experience for setting up Kerberos authentication with SQL Server and PostgreSQL databases. New features from PR #151 enhance the experience with better visual feedback and comprehensive diagnostics.

## 📋 What the Wizard Does

The wizard walks you through a complete Kerberos setup in clearly marked sections:

1. **Prerequisites Check** - Validates your environment is ready
2. **Configuration Detection** - Finds existing Kerberos settings
3. **Domain Setup** - Configures your corporate realm
4. **Service Configuration** - Sets up the Kerberos sidecar container
5. **Connection Testing** - Optionally validates database connections
6. **Completion** - Confirms successful setup

## 🎨 Visual Experience

### Section Headers
The wizard uses visual section dividers to clearly show progress:

```
==================================================
Kerberos Configuration
==================================================
```

### Subsection Headers
Database testing sections have their own clear headers:

```
--------------------------------------------------
SQL Server Connection Test
--------------------------------------------------
```

### Status Indicators
Clear visual feedback throughout:
- ✓ Success markers for completed steps
- ✗ Error indicators with helpful messages
- ⚠ Warnings for non-critical issues
- ℹ Information messages for context

## 🔍 Smart Diagnostics

When issues occur, the wizard provides targeted help based on the specific error:

### krb5.conf Parsing
The wizard automatically parses your `/etc/krb5.conf` to:
- Extract configured realms and KDCs
- Validate domain mappings
- Suggest corrections for common misconfigurations

### Connection Failures
If database connections fail, you'll see:
- Current Kerberos ticket status
- Network connectivity checks
- DNS resolution verification
- Specific troubleshooting steps for your error

Example diagnostic output:
```
Connection failed: Unable to authenticate

Diagnostics:
✓ Kerberos ticket valid (expires in 8h)
✗ Cannot resolve sqlserver.company.com
  → Check DNS settings or use IP address
✓ Network route to KDC available
ℹ Detected realm: COMPANY.COM
```

## 🗂️ Database Connection Testing

The wizard now supports testing both SQL Server and PostgreSQL connections:

### SQL Server Testing
When you have a SQL Server instance available:
1. Wizard prompts for the FQDN
2. Runs connection test using `sqlcmd-test` container
3. Validates Kerberos authentication
4. Shows detailed results or diagnostics

### PostgreSQL Testing
For PostgreSQL with GSSAPI/Kerberos:
1. Wizard prompts for the PostgreSQL FQDN
2. Uses `postgres-test` container for validation
3. Confirms Kerberos ticket usage
4. Provides connection diagnostics if needed

## 💡 Progressive Disclosure

The wizard follows progressive disclosure principles:
- **Essential information first** - Only shows what you need at each step
- **Details on demand** - Error diagnostics appear only when needed
- **Clear next steps** - Always tells you what comes next
- **Skip optional steps** - Can bypass database testing if not needed

## 📝 What Gets Configured

After successful completion, the wizard will have:

1. **Created platform-config.yaml** with your settings
2. **Generated .env file** with:
   - Kerberos domain configuration
   - Container image settings
   - Prebuilt/build mode flags
3. **Started services**:
   - Kerberos sidecar container
   - Platform PostgreSQL (if selected)
   - OpenMetadata (if selected)

## 🚨 Troubleshooting

### If the Wizard Fails

The wizard saves state and can resume:
```bash
# Resume from where you left off
./dev-tools/setup-kerberos.sh --resume

# Or start fresh
./dev-tools/setup-kerberos.sh --reset
```

### Common Issues

**"Prerequisites check failed"**
- Install missing packages: `sudo apt-get install krb5-user`
- Ensure Docker is running: `docker info`

**"Cannot detect Kerberos configuration"**
- Create `/etc/krb5.conf` with your corporate settings
- See [Kerberos Progressive Validation](kerberos-progressive-validation.md) for details

**"Connection test failed"**
- Check the comprehensive diagnostics provided
- Verify your ticket: `klist`
- Test network connectivity to the database server

## 🔗 Related Documentation

- **[Getting Started](getting-started-simple.md)** - Main setup guide
- **[Kerberos Progressive Validation](kerberos-progressive-validation.md)** - Detailed validation steps
- **[Platform Architecture](platform-architecture-vision.md)** - Overall system design

## 📊 Example Wizard Session

Here's what a typical successful run looks like:

```
╔════════════════════════════════════════════════════════════════╗
║          Kerberos Setup Wizard for Airflow Development          ║
╚════════════════════════════════════════════════════════════════╝

==================================================
Step 1/11: Checking Prerequisites
==================================================
✓ Docker is installed and running
✓ krb5-user package installed
✓ /etc/krb5.conf found

==================================================
Step 2/11: Detecting Kerberos Configuration
==================================================
✓ Found realm: COMPANY.COM
✓ KDC: kdc.company.com
✓ Valid ticket found (expires in 9h)

==================================================
Step 3/11: Domain Configuration
==================================================
Enter Kerberos domain (e.g., COMPANY.COM): COMPANY.COM
✓ Domain validated

[... continues through all steps ...]

==================================================
Kerberos Setup Complete!
==================================================
✓ Kerberos sidecar running
✓ Configuration saved to platform-config.yaml
✓ Environment file created at .env

Next steps:
• Start using platform: make platform-start
• Test SQL Server: ./diagnostics/test-sql-direct.sh
• View logs: docker logs kerberos-platform-service
```

---

*The enhanced Kerberos wizard provides a streamlined, user-friendly experience with clear visual feedback and intelligent diagnostics to help you successfully configure authentication for your data platform.*