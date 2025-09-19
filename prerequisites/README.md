# Prerequisites Directory

**⚠️ Note**: This directory contains legacy setup components. For new installations, use the [modern Ansible automation](../README-PLATFORM-SETUP.md) instead.

## What's Here

This directory contains the individual components used by the platform setup:

### Legacy Components
- **certificates/**: PowerShell scripts for Windows certificate generation
- **traefik-registry/**: Docker Compose configuration for services
- **windows-wsl2/**: Manual setup steps (now automated)

### Current Status
These components are still used internally by the automation but are **not recommended for manual setup**.

## Recommended Approach

Instead of using these files directly:

```bash
# Use modern Ansible automation
cd /path/to/workstation-setup
ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml
```

See [README-PLATFORM-SETUP.md](../README-PLATFORM-SETUP.md) for complete setup instructions.

## Legacy Manual Setup

If you must use manual setup (not recommended):

1. **Windows**: Run `certificates/setup-dev-certs-hybrid.ps1`
2. **WSL2**: Follow steps in `windows-wsl2/setup-steps.txt`
3. **Services**: Deploy `traefik-registry/docker-compose.yml`

**Problems with manual setup:**
- Brittle certificate management
- Manual host file editing required
- No validation or error handling
- Difficult to teardown and rebuild

## Migration Path

If you have an existing manual setup:

```bash
# Clean up old setup
./scripts/teardown.sh

# Migrate to modern automation
ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml
```

---

*For new installations, skip this directory and use [README-PLATFORM-SETUP.md](../README-PLATFORM-SETUP.md)*