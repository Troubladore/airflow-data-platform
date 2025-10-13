# Kerberos Setup Wizard

An interactive, step-by-step wizard that guides developers through the complete Kerberos authentication setup for Docker-based Airflow development with SQL Server.

## Overview

The Kerberos Setup Wizard (`setup-kerberos.sh`) is a comprehensive, user-friendly tool that:

- Checks prerequisites and validates configurations
- Guides through Kerberos ticket acquisition
- Auto-detects ticket locations and configurations
- Updates `.env` files automatically (with confirmation)
- Builds and starts all required services
- Tests the complete setup end-to-end
- Provides clear troubleshooting guidance

## Quick Start

```bash
# From the platform-bootstrap directory
make kerberos-setup

# Or directly
./setup-kerberos.sh
```

## Features

### 1. Interactive Guidance
- **Step-by-step progression**: 10 clear steps with progress tracking
- **Color-coded output**: Green ✓ for success, red ✗ for errors, yellow ⚠ for warnings
- **Clear prompts**: User-friendly questions with sensible defaults
- **Help text**: Contextual guidance at each step

### 2. Resume Capability
If interrupted, the wizard can resume from where it left off:

```bash
# Resume from saved progress
./setup-kerberos.sh --resume

# Start fresh (clear saved progress)
./setup-kerberos.sh --reset
```

The wizard automatically detects incomplete runs and offers to resume.

### 3. Automatic Detection
- Windows domain and username (in WSL2 environments)
- Kerberos ticket cache location and type (FILE, DIR, KCM)
- Kerberos realm from krb5.conf
- Existing Kerberos tickets and their expiration

### 4. Smart Configuration
- Validates `.env` file or creates from template
- Shows current vs. detected configuration
- Updates `.env` with auto-detected values (with confirmation)
- Handles both FILE and DIR ticket cache types
- Preserves existing settings when appropriate

### 5. Comprehensive Testing
- KDC reachability test
- Ticket sharing verification
- Optional SQL Server connection test
- Provides detailed troubleshooting if tests fail

### 6. Error Handling
- Graceful failure handling at each step
- Specific error messages with actionable fixes
- Option to skip optional steps
- Summary of what worked vs. needs attention

## The 10 Steps

### Step 1: Check Prerequisites
Verifies:
- `krb5-user` package (klist, kinit)
- Docker and Docker daemon
- Docker Compose v2+

**On Failure**: Provides specific installation commands

### Step 2: Validate krb5.conf
Checks:
- `/etc/krb5.conf` exists
- Extracts default realm
- Shows relevant configuration

**On Failure**: Guides on obtaining correct configuration

### Step 3: Test KDC Reachability
Tests:
- Connection to Kerberos KDC (port 88)
- Network connectivity
- VPN status

**On Failure**: Suggests VPN connection, network checks

### Step 4: Check Kerberos Ticket
Options:
- Use existing valid ticket
- Obtain new ticket interactively
- Auto-suggests username/domain

**On Failure**: Provides troubleshooting for kinit issues

### Step 5: Detect Ticket Location
Runs:
- `diagnose-kerberos.sh` for comprehensive detection
- Parses ticket cache type, path, and filename
- Shows detected configuration

**On Failure**: Offers manual configuration in next step

### Step 6: Update .env Configuration
Actions:
- Shows current `.env` settings
- Displays detected values
- Updates `.env` with confirmation
- Option for manual editing

**Key Variables Configured**:
```bash
COMPANY_DOMAIN=COMPANY.COM
KERBEROS_CACHE_TYPE=FILE      # or DIR
KERBEROS_CACHE_PATH=/path/to/cache
KERBEROS_CACHE_TICKET=ticket_filename
```

### Step 7: Build Sidecar Image
Checks:
- Existing `platform/kerberos-sidecar:latest` image
- Builds if missing
- Uses kerberos-sidecar Makefile

**On Failure**: Shows common build issues and solutions

### Step 8: Start Services
Sets up:
- Docker network: `platform_network`
- Docker volume: `platform_kerberos_cache`
- Starts services with `docker compose up -d`

**Shows**: Running services status

### Step 9: Test Ticket Sharing
Runs:
- Simple ticket sharing test
- Uses `test_kerberos_simple.py`
- Verifies tickets accessible in containers

**On Success**: Confirms ticket sharing works
**On Failure**: Provides troubleshooting steps

### Step 10: Test SQL Server (Optional)
Optionally:
- Tests connection to real SQL Server
- Interactive server/database input
- Uses `test-kerberos.sh`

**Skippable**: Can skip if no test server available

## Usage Examples

### First-Time Setup
```bash
cd airflow-data-platform/platform-bootstrap
make kerberos-setup

# Follow prompts through all 10 steps
# Wizard will guide you completely
```

### Resume After Interruption
```bash
# If wizard was interrupted (Ctrl+C, network issue, etc.)
./setup-kerberos.sh --resume

# Starts from last completed step
```

### Reconfigure Existing Setup
```bash
# Clear saved state and start fresh
./setup-kerberos.sh --reset

# Or just run normally (it will ask)
make kerberos-setup
```

### Get Help
```bash
./setup-kerberos.sh --help
```

## Output Examples

### Successful Step
```
═══════════════════════════════════════════════════════════════
Step 4/10: Checking for Kerberos Ticket
═══════════════════════════════════════════════════════════════

Checking for active Kerberos ticket... ✓ Found

Current ticket details:
----------------------------------------
  Ticket cache: DIR::/home/user/.krb5-cache/dev
  Default principal: jsmith@COMPANY.COM
  Expires: 2025-10-12 20:00:00
----------------------------------------

ℹ  Principal: jsmith@COMPANY.COM
ℹ  Expires: 2025-10-12 20:00:00

Would you like to use this ticket? [Y/n]: y
✓ Using existing ticket
```

### Error with Guidance
```
═══════════════════════════════════════════════════════════════
Step 9/10: Testing Kerberos Ticket Sharing
═══════════════════════════════════════════════════════════════

ℹ  Running simple ticket sharing test...

✗ Ticket sharing test FAILED

Test output saved to: /tmp/kerberos-test-output.txt

⚠  Kerberos may not be configured correctly

  Troubleshooting steps:
  1. Check service logs: docker compose logs
  2. Verify .env configuration: cat .env
  3. Run diagnostic: ./diagnose-kerberos.sh
  4. Check ticket: klist

Continue anyway? [y/N]:
```

### Final Summary
```
╔════════════════════════════════════════════════════════════════╗
║                    Setup Complete!                             ║
╚════════════════════════════════════════════════════════════════╝

Configuration Summary:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  COMPANY_DOMAIN=COMPANY.COM
  KERBEROS_CACHE_TYPE=DIR
  KERBEROS_CACHE_PATH=${HOME}/.krb5-cache
  KERBEROS_CACHE_TICKET=dev/tkt
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Running Services:
  NAME                        STATUS    PORTS
  kerberos-platform-service   Up
  mock-delinea                Up        0.0.0.0:8443->1080/tcp

What's Next:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. Create or start your Airflow project:
     astro dev init my-project    # New project
     cd my-project && astro dev start

  2. Your Airflow containers will automatically have access to:
     • Kerberos tickets (for SQL Server authentication)
     • Shared network (platform_network)

  3. Useful commands:
     make platform-status       # Check service status
     make kerberos-test         # Verify Kerberos ticket
     make test-kerberos-simple  # Test ticket sharing
     docker compose logs        # View service logs

  4. Managing Kerberos tickets:
     klist                      # Check ticket status
     kinit jsmith@COMPANY.COM   # Renew ticket
     ./diagnose-kerberos.sh     # Troubleshoot issues

  5. When done for the day:
     make platform-stop         # Stop all services

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ  Your domain: COMPANY.COM
ℹ  Your username: jsmith

✓ Kerberos setup is complete and ready to use!
```

## Integration Points

### Makefile Integration
```makefile
kerberos-setup: ## Interactive wizard to set up Kerberos from scratch
	@./setup-kerberos.sh
```

Usage: `make kerberos-setup`

### Documentation References
- **Getting Started Guide**: Recommends wizard for first-time setup
- **Troubleshooting**: Points to wizard for configuration issues
- **Kerberos Setup WSL2**: References wizard as automated alternative

### Tool Dependencies
The wizard uses these existing tools:
- `diagnose-kerberos.sh` - For ticket detection
- `test_kerberos_simple.py` - For basic ticket sharing test
- `test-kerberos.sh` - For SQL Server connection test
- `kerberos-sidecar/Makefile` - For building sidecar image

## Design Principles

### 1. User Experience
- **Clear progress**: Always show what step and why
- **No surprises**: Ask before making changes
- **Good defaults**: Suggest sensible values
- **Helpful errors**: Specific fixes, not just "failed"

### 2. Safety
- **Idempotent**: Can be re-run safely
- **Non-destructive**: Preserves existing configs
- **Confirmations**: Ask before overwriting
- **Resume capability**: Save progress, handle interruptions

### 3. Intelligence
- **Auto-detection**: Minimize manual input
- **Context awareness**: WSL2 vs. Linux, existing tickets
- **Smart defaults**: Use detected values
- **Validation**: Test each step before proceeding

### 4. Transparency
- **Show commands**: Display what will run
- **Explain choices**: Why certain values
- **Log output**: Save diagnostic information
- **Clear results**: What worked, what needs attention

## Troubleshooting

### Wizard Won't Start
```bash
# Check script permissions
ls -la setup-kerberos.sh
# Should be: -rwxr-xr-x

# Fix if needed
chmod +x setup-kerberos.sh
```

### Resume Not Working
```bash
# Check for state file
ls -la /tmp/.kerberos-setup-state

# Clear and restart
./setup-kerberos.sh --reset
```

### Auto-Detection Fails
The wizard will:
1. Run full diagnostic
2. Save output to `/tmp/kerberos-diagnostic.log`
3. Offer manual configuration
4. Guide through each required value

### Test Failures
Each test shows:
- Exact error message
- Relevant log files
- Specific troubleshooting steps
- Option to continue or retry

## Advanced Usage

### Skip Certain Steps
While the wizard is interactive, you can manually skip optional steps when prompted:
- KDC reachability test (if offline)
- SQL Server connection test (if no test server available)

### Pre-configure Environment
Set these before running for less interaction:
```bash
export DETECTED_DOMAIN="COMPANY.COM"
export DETECTED_USERNAME="jsmith"
```

### Debug Mode
View detailed execution:
```bash
bash -x ./setup-kerberos.sh
```

## Comparison with Manual Setup

| Aspect | Manual Setup | Wizard |
|--------|-------------|--------|
| Time | 30-60 minutes | 10-15 minutes |
| Errors | Common | Prevented |
| Documentation | Must reference multiple docs | Self-guided |
| Testing | Manual | Automated |
| Resume | Must start over | Can resume |
| Troubleshooting | Must diagnose yourself | Guided help |

## Future Enhancements

Potential additions:
- [ ] Support for KCM ticket format
- [ ] Keytab file configuration
- [ ] Multiple realm support
- [ ] Export configuration for team sharing
- [ ] Automated renewal setup
- [ ] Integration with CI/CD for testing

## Related Documentation

- [Getting Started Guide](../docs/getting-started-simple.md) - Overall platform setup
- [Kerberos Diagnostic Guide](../docs/kerberos-diagnostic-guide.md) - Understanding diagnose-kerberos.sh
- [Kerberos Setup WSL2](../docs/kerberos-setup-wsl2.md) - Detailed manual setup
- [Kerberos Progressive Validation](../docs/kerberos-progressive-validation.md) - Testing guide

## Support

If you encounter issues:
1. Run with debug: `bash -x ./setup-kerberos.sh`
2. Check logs: `/tmp/kerberos-diagnostic.log`
3. Run manual diagnostic: `./diagnose-kerberos.sh`
4. Review documentation in `docs/` directory
5. Open an issue with wizard output

---

**Ready to start?** Run `make kerberos-setup` and let the wizard guide you through the complete setup process!
