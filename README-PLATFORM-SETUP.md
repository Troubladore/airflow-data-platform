# Platform Setup Guide

**🎯 Quick Start for the Astronomer Airflow Data Engineering Platform**

This guide provides clear workflows for setting up your development environment from scratch. Choose the method that fits your environment and permissions.

## 🖥️ Environment Support

**Current Target**: Windows + WSL2 (Ubuntu 24.04)
- All commands clearly marked with 🪟 (Windows PowerShell) or 🐧 (WSL2 Ubuntu terminal)
- Cross-platform automation from WSL2 manages both Windows and Linux components

**Future Support**: Pure Ubuntu environments
- Ansible playbooks designed to work on native Ubuntu (no Windows components)
- Path prepared for full Linux development environments

## 🚀 Recommended Setup (Ansible Automation)

**Best choice: Handles both admin and non-admin environments gracefully**

> 🤖 **Technical Deep Dive**: Curious how Ansible running in WSL2 can manage Windows operations? See [Technical Architecture: WSL2 + Ansible + WinRM](docs/TECHNICAL-ARCHITECTURE.md) for the fascinating details behind cross-platform orchestration.

### Prerequisites
```bash
# 🐧 Run in WSL2 Ubuntu terminal
# Use pipx for clean global installs (recommended)
sudo apt update && sudo apt install -y pipx
pipx ensurepath

# Install pinned Ansible dependencies
cd <<your_repo_folder>>/workstation-setup
./scripts/install-pipx-deps.sh

# Install Ansible Galaxy dependencies
ansible-galaxy install -r ansible/requirements.yml

# Or fallback to pip
# pip install --user -r ansible/requirements.txt
```

### Complete Setup

**Option A: Non-Windows-Admin (Recommended)**
```bash
# 🐧 Run in WSL2 Ubuntu terminal - no Windows admin privileges required
cd <<your_repo_folder>>/workstation-setup
./scripts/setup-windows-prereqs.sh

# Then run platform setup (you'll be prompted for your sudo password)
ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml --ask-become-pass
```

**Option B: Windows Admin Users with WinRM**
```bash
# 🐧 Run in WSL2 Ubuntu terminal (requires Windows admin + WinRM setup)
cd <<your_repo_folder>>/workstation-setup
ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml --ask-become-pass
```

### Validation
```bash
# 🐧 Run in WSL2 Ubuntu terminal
ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-all.yml --ask-become-pass --ask-become-pass
```

**Expected Results:**
- ✅ `https://traefik.localhost` - Traefik dashboard
- ✅ `https://registry.localhost/v2/_catalog` - Container registry
- ✅ Docker push/pull operations work

---

## 🔄 Testing & Development Workflow

### Complete Environment Reset
```bash
# 🐧 Run in WSL2 Ubuntu terminal
./scripts/teardown.sh

# Choose certificate cleanup level:
# 1) Keep certificates (fast rebuild)
# 2) Remove WSL2 certificates only
# 3) Manual cleanup guide for complete removal

# Rebuild environment
ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml
```

### Quick Validation After Changes
```bash
# 🐧 Run in WSL2 Ubuntu terminal
# Test specific components
ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-all.yml --ask-become-pass

# Or manually test key endpoints
curl -k https://registry.localhost/v2/_catalog
curl -k https://traefik.localhost/api/http/services
```

---

## 🪟 Corporate/Non-Admin Environment Setup

**Great news: Most tasks work without admin rights!**

### What Ansible Does Automatically (No Admin Required)
- ✅ Install Scoop package manager
- ✅ Install mkcert via Scoop
- ✅ Install local CA (`mkcert -install`)
- ✅ Generate development certificates
- ✅ Copy certificates to WSL2
- ✅ Deploy and configure all services

### Only Manual Step Required
**Update hosts file** (requires admin rights OR corporate tool):
```
127.0.0.1 registry.localhost
127.0.0.1 traefik.localhost
```

### Recommended Workflow
```bash
# 🐧 Run in WSL2 Ubuntu terminal
# Run full automation (will handle everything except hosts file)
ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml

# If hosts file update fails, Ansible will provide clear guidance
# 🪟 Add entries via your corporate host management tool (Windows side)
# 🐧 Re-run to validate (back in WSL2 terminal)
ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-all.yml --ask-become-pass
```

---

## 🛠️ Legacy/Manual Setup

**If Ansible is not available or preferred**

```bash
# 🐧 Run in WSL2 Ubuntu terminal
# Traditional script-based setup
./scripts/setup.sh

# The script will detect Ansible and offer to use it
# Choose 'n' to proceed with manual setup
```

**Note**: Manual setup requires more manual intervention for certificate generation and host file updates.

---

## 📊 What Gets Set Up

### Core Services
- **Traefik Reverse Proxy**: Routes HTTPS traffic to services
- **Docker Container Registry**: Local registry for custom images
- **Development Certificates**: TLS certificates for *.localhost domains

### Network Configuration
- **Windows Hosts**: Entries for local service resolution
- **WSL2 Certificates**: Proper certificate placement for containers
- **Docker Integration**: Traefik connected to Docker daemon for service discovery

### Validation Systems
- **Health Checks**: Automated testing of all components
- **Registry Operations**: Push/pull testing to verify functionality
- **TLS Validation**: Certificate chain and trust verification

---

## 🚨 Troubleshooting

### Common Issues

**"Permission Denied" on Windows tasks**
- Expected for non-admin users
- Follow manual prerequisites section above
- Re-run with validation to confirm setup

**"Docker not found in WSL2"**
- Enable Docker Desktop WSL2 integration
- Settings → Resources → WSL Integration → Enable for your distro
- Restart WSL2: `wsl --shutdown` then reopen

**"Certificate/HTTPS errors"**
- Ensure mkcert CA is installed: `mkcert -install`
- Check certificates exist: `ls ~/.local/share/certs/`
- Verify hosts file has required entries

### Get Help
```bash
# Check detailed validation results
ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-all.yml --ask-become-pass

# View container logs
docker compose -f ~/platform-services/traefik/docker-compose.yml logs -f

# Test manual connections
curl -k https://registry.localhost/v2/_catalog
```

---

## 🎯 Success Criteria

After successful setup, you should have:

✅ **HTTPS Services Working**
- Traefik dashboard accessible at https://traefik.localhost
- Container registry accessible at https://registry.localhost
- No certificate warnings in browser

✅ **Docker Registry Functional**
- Can push images: `docker push registry.localhost/test/image:tag`
- Can pull images: `docker pull registry.localhost/test/image:tag`
- Registry catalog shows pushed images

✅ **Development Ready**
- All validation tests pass
- Platform ready for Airflow project deployment
- Ready to build custom images and deploy services

---

*This platform foundation enables the complete Astronomer Airflow data engineering environment. Once set up, proceed to deploy your first Airflow project using the examples and guides.*
