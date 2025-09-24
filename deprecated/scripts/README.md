# Deprecated Scripts

These scripts were moved here during the repository simplification to align with Astronomer architecture.

## What Was Moved Here

### Certificate Management Scripts
- Various certificate setup, trust, and diagnostic scripts
- Windows PowerShell scripts for certificate management
- Browser access testing scripts
- Certificate chain verification utilities

**Why deprecated**: Astronomer handles TLS/certificates. Local development doesn't need complex certificate infrastructure.

### Layer2 Component Scripts
- `build-layer2-components.sh`
- `test-layer2-components.sh`
- `teardown-layer2.sh`

**Why deprecated**: Layer2 datakits pattern moved to examples repository.

### Platform Build Scripts
- `build-all.sh`
- `build-platform-images.sh`
- `setup.sh`
- `teardown.sh`
- `clean-slate.sh`

**Why deprecated**: Astronomer provides the platform. We don't build our own anymore.

### Windows-Specific Scripts
- Various `.bat` and `.ps1` scripts for Windows setup
- Windows prerequisite installation scripts

**Why deprecated**: Simplified approach using WSL2 native tools.

### Validation Scripts
- `validate-platform-complete.sh`
- `verify.sh`
- Various test scripts for platform components

**Why deprecated**: Testing now focused on framework components, not platform infrastructure.

## What We Kept

Only 4 essential scripts remain in `/scripts/`:
1. `test-with-postgres-sandbox.sh` - Still useful for SQLModel framework testing
2. `install-pipx-deps.sh` - Development dependencies setup
3. `scan-supply-chain.sh` - Security scanning remains important
4. `run-tests.sh` - Simple test runner for the framework

## Migration Notes

If you need any of these deprecated scripts:
- Certificate issues: Use Astronomer's built-in certificate handling
- Platform building: Use `astro dev start` instead
- Layer2 components: See airflow-data-platform-examples repository
- Windows setup: Follow the simplified WSL2 guide in docs
