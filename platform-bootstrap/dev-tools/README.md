# Development Tools

This directory contains scripts used during development, setup, and testing. These are NOT deployed to production environments.

## Setup and Configuration

### `setup-kerberos.sh`
Interactive setup wizard for Kerberos configuration in development environments.

**Usage:**
```bash
./setup-kerberos.sh
```

**Features:**
- Interactive configuration wizard
- Environment detection (corporate/MIT)
- Generates .env configuration
- Validates prerequisites

### `setup-hooks.sh`
Installs Git hooks for code quality enforcement.

**Usage:**
```bash
./setup-hooks.sh
```

**Features:**
- Installs pre-push validation hook
- Prevents pushing broken scripts
- Ensures demo-safe code

### `run-kerberos-setup.sh`
Wrapper that runs setup with dual logging (screen + file).

**Usage:**
```bash
./run-kerberos-setup.sh
```

**Output:**
- Screen display for interactive use
- Log file: `kerberos-setup-TIMESTAMP.log`

## Cleanup and Maintenance

### `clean-slate.sh`
Removes all platform Docker resources for a fresh start.

**Usage:**
```bash
./clean-slate.sh
```

**Features:**
- Interactive prompts for selective cleanup
- Preserves configuration files
- Options for image/cache removal

## Test Variations

These are experimental or alternative test implementations:

### `test-sql-container.sh`
Container-based SQL test with custom image builds.

### `test-sql-direct-v2.sh`
Enhanced version of direct SQL testing.

### `test-sql-prebuilt.sh`
Uses pre-built test images for faster testing.

### `test-kerberos.sh`
Basic Kerberos functionality tests.

## Development Workflow

### Initial Setup
```bash
# 1. Configure Kerberos
./dev-tools/setup-kerberos.sh

# 2. Install Git hooks
./dev-tools/setup-hooks.sh

# 3. Run tests
./tests/dry-run-all-scripts.sh
```

### Clean Restart
```bash
# Remove all Docker artifacts
./dev-tools/clean-slate.sh

# Reconfigure
./dev-tools/setup-kerberos.sh
```

### Before Committing
```bash
# Validate all scripts
./tests/dry-run-all-scripts.sh

# Git hooks will auto-validate on push
git push  # Runs validation automatically
```

## Directory Structure

```
platform-bootstrap/
├── diagnostics/          # Production diagnostic tools
│   ├── krb5-auth-test.sh
│   ├── diagnose-kerberos.sh
│   └── ...
├── dev-tools/           # Development-only scripts
│   ├── setup-kerberos.sh
│   ├── clean-slate.sh
│   └── ...
├── tests/               # Test suites
│   ├── dry-run-all-scripts.sh
│   └── test-shell-syntax.sh
├── lib/                 # Shared libraries
│   └── formatting.sh
└── .githooks/           # Git hooks
    └── pre-push
```

## Best Practices

1. **Keep dev-tools separate** - Never deploy these to production
2. **Use clean-slate for fresh starts** - Removes all Docker state
3. **Run tests before pushing** - Hooks enforce this automatically
4. **Use the setup wizard** - Ensures correct configuration

## Environment Variables

Development tools use these files:

- `.env` - Generated configuration (git-ignored)
- `.env.example` - Template configuration

## Security Notes

- Development tools may modify system state
- Not designed for production use
- May require elevated permissions
- Use clean-slate to remove all artifacts