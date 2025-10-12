# Kerberos Diagnostic Tool - Complete Guide

The `diagnose-kerberos.sh` tool automatically detects your Kerberos configuration and provides exact values for your `.env` file. This guide explains how to use it and understand its recommendations.

## 🎯 What the Diagnostic Tool Does

The diagnostic tool:
1. Detects your current Kerberos ticket location and format
2. Provides exact `.env` configuration values
3. Tests Docker volume and network setup
4. Verifies ticket sharing between WSL2 and Docker containers
5. Offers specific fixes based on your setup

## 🚀 Running the Diagnostic Tool

```bash
cd airflow-data-platform/platform-bootstrap
./diagnose-kerberos.sh

# Or using make:
make kerberos-diagnose
```

## 📊 Understanding Ticket Formats

Your organization's Kerberos setup will use one of these ticket storage formats:

### FILE Format (Most Common)
```
Ticket cache: FILE:/tmp/krb5cc_1000
```
- **What it is**: A single file containing your Kerberos ticket
- **Location**: Usually in `/tmp/` with a name like `krb5cc_1000`
- **Pros**: Simple, widely compatible, easy to share with Docker
- **Cons**: Only one active ticket at a time
- **Best for**: Most users, especially those with single domain access

### DIR Format (Directory Collections)
```
Ticket cache: DIR::/home/username/.krb5-cache/dev/tkt
```
- **What it is**: A directory containing multiple ticket files
- **Location**: Often in home directory like `~/.krb5-cache/`
- **Pros**: Can store multiple tickets for different services/realms
- **Cons**: Slightly more complex to configure
- **Best for**: Users accessing multiple Kerberos realms or services

### KCM Format (Kernel Keyring)
```
Ticket cache: KCM:
```
- **What it is**: Tickets stored in kernel memory
- **Location**: Not a file - stored in system memory
- **Pros**: More secure, managed by the OS
- **Cons**: Cannot be shared with Docker containers
- **Action Required**: Must convert to FILE format (see below)

## 🔧 Configuration Options Explained

When the diagnostic tool detects your tickets, you have two main options:

### Option A: Use Your Current Format (Recommended)

The tool will show you exact `.env` values like:
```bash
KERBEROS_CACHE_TYPE=DIR
KERBEROS_CACHE_PATH=${HOME}/.krb5-cache
KERBEROS_CACHE_TICKET=dev/tkt
```

**Advantages**:
- No changes to your existing Kerberos workflow
- Works with your organization's standard setup
- Tickets continue to work with other tools

**When to use**:
- Your organization has a standard Kerberos setup
- You don't want to change how you get tickets
- The diagnostic tool successfully detects your configuration

### Option B: Convert to Standard FILE Format

If you're having issues or want a simpler setup:
```bash
export KRB5CCNAME=FILE:/tmp/krb5cc_$(id -u)
kinit YOUR_USERNAME@DOMAIN.COM
```

**Advantages**:
- Simpler configuration
- Most compatible with Docker
- Easier to troubleshoot

**When to use**:
- You have KCM format (required)
- Your organization allows flexibility in ticket location
- You're experiencing issues with directory-based tickets

## 📋 Diagnostic Tool Output Sections

### Section 1: Host Kerberos Tickets
Shows if you have valid tickets and their location.

**What to look for**:
- ✅ "Kerberos tickets found!" - You have valid tickets
- ❌ "No Kerberos tickets found" - Run `kinit` first

### Section 2: Common Ticket Locations
Searches standard locations for ticket files.

**What to look for**:
- ✅ "Found ticket at: /path/to/ticket" - Tickets detected
- ❌ "No tickets found in common locations" - May need custom configuration

### Section 3: Docker Environment
Verifies Docker setup for ticket sharing.

**What to look for**:
- ✅ "Docker is running" - Docker is ready
- ✅ "platform_network exists" - Network configured
- ✅ "platform_kerberos_cache volume exists" - Volume ready for tickets

### Section 4: Ticket Sharing Test
Tests if tickets can be accessed from containers.

**What to look for**:
- ✅ "krb5cc file found" - Tickets are being shared successfully

### Section 5: EXACT .ENV CONFIGURATION (Most Important!)

This section provides the exact values to put in your `.env` file:

```bash
----------------------------------------
# Add to platform-bootstrap/.env
KERBEROS_CACHE_TYPE=FILE
KERBEROS_CACHE_PATH=/tmp
KERBEROS_CACHE_TICKET=krb5cc_1000
----------------------------------------
```

**Quick Setup Options**:

1. **Manual Setup**: Copy the values and edit `.env` yourself
2. **Automatic Setup**: Run the provided command to update `.env` automatically

### Section 6: Additional Recommendations
Context-specific advice based on your setup.

### Section 7: Quick Fixes
Step-by-step commands to resolve any issues found.

## 🛠️ Common Scenarios and Solutions

### Scenario 1: Fresh WSL2 Installation
```bash
# Install Kerberos first
sudo apt-get update
sudo apt-get install -y krb5-user

# Get your first ticket
kinit YOUR_USERNAME@DOMAIN.COM

# Run diagnostic
./diagnose-kerberos.sh

# Copy the .env values it provides
# Start services
make platform-start
```

### Scenario 2: KCM Format Detected
```bash
# The diagnostic will tell you to convert to FILE format:
export KRB5CCNAME=FILE:/tmp/krb5cc_$(id -u)
kinit YOUR_USERNAME@DOMAIN.COM

# Run diagnostic again
./diagnose-kerberos.sh

# Now it will provide proper .env values
```

### Scenario 3: Directory Collection (DIR Format)
```bash
# The diagnostic will automatically detect and configure:
# KERBEROS_CACHE_TYPE=DIR
# KERBEROS_CACHE_PATH=${HOME}/.krb5-cache
# KERBEROS_CACHE_TICKET=dev/tkt

# Just copy these values to .env and start
```

### Scenario 4: Custom Organization Setup
If your organization uses a non-standard location:
```bash
# The diagnostic will detect it and provide exact values
# For example:
# KERBEROS_CACHE_TYPE=FILE
# KERBEROS_CACHE_PATH=${HOME}/.corporate/tickets
# KERBEROS_CACHE_TICKET=krb_cache

# These will work automatically with the platform
```

## 🔄 How Ticket Sharing Works

Understanding the flow helps troubleshoot issues:

1. **You get a ticket**: `kinit` creates a ticket file in WSL2
2. **Diagnostic detects location**: Finds where your ticket is stored
3. **You configure .env**: Tells Docker where to find tickets
4. **Docker mounts location**: The compose file mounts your ticket directory
5. **Sharing service copies tickets**: Copies to shared volume every 5 minutes
6. **Containers access tickets**: All containers can use the shared volume

## ❓ Frequently Asked Questions

### Q: Why does the diagnostic recommend FILE format over DIR?
**A**: FILE format is simpler and more universally compatible. However, if your organization uses DIR format as standard, stick with it - the platform handles both.

### Q: Can I use multiple Kerberos realms?
**A**: Yes, with DIR format. Each realm gets its own ticket file in the directory.

### Q: How often are tickets refreshed in Docker?
**A**: Every 5 minutes. The sharing service automatically copies new tickets.

### Q: What if my tickets expire?
**A**: Run `kinit` again to get new tickets. The sharing service will pick them up automatically.

### Q: Can I change the ticket location after initial setup?
**A**: Yes, update your `.env` file and restart services with `make platform-restart`.

## 🚨 Troubleshooting

### "No tickets found" but I have tickets
1. Check your `KRB5CCNAME` environment variable: `echo $KRB5CCNAME`
2. Verify ticket location: `klist`
3. Ensure the diagnostic has permission to read the location

### ".env values don't work"
1. Ensure no trailing spaces in `.env` file
2. Check that paths use `${HOME}` not `~`
3. Verify the ticket file actually exists at the specified location

### "Docker can't access tickets"
1. Ensure Docker service is running: `docker ps`
2. Check volume exists: `docker volume ls | grep kerberos`
3. Verify network exists: `docker network ls | grep platform`

### "Tickets work in WSL2 but not in containers"
1. Run the diagnostic to get fresh configuration
2. Ensure the sharing service is running: `docker ps | grep kerberos`
3. Check service logs: `docker logs kerberos-platform-service`

## 📚 Related Documentation

- [Main Kerberos Setup Guide](kerberos-setup-wsl2.md)
- [Platform Bootstrap README](../platform-bootstrap/README.md)
- [Daily Developer Workflow](getting-started-simple.md#-daily-workflow)

## 💡 Best Practices

1. **Run the diagnostic first**: Before manual configuration, let it detect your setup
2. **Use the automatic update**: The tool provides a command to update `.env` automatically
3. **Keep tickets fresh**: Set up a cron job or reminder to renew tickets daily
4. **Test after changes**: Always run `make test-kerberos-simple` after configuration changes
5. **Check logs if issues arise**: `docker logs kerberos-platform-service` shows what's happening

---

*This guide is part of the airflow-data-platform Kerberos integration documentation.*
