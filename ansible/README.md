# Ansible Platform Setup

Automated setup for the Astronomer Airflow data engineering platform with graceful handling of admin permissions.

## 🎯 Strategy

This automation uses a **"try to fix, fail gracefully"** approach:
- ✅ **Local admin users**: Full automation of all prerequisite steps
- ⚠️ **Non-admin users**: Clear guidance for manual steps with validation

## 📋 Prerequisites

### Install Ansible (WSL2 Ubuntu Terminal)
```bash
# 🐧 Run in WSL2 Ubuntu terminal
# Use pipx for isolated global installs (avoids dependency conflicts)

# Install pipx if not already present
sudo apt update && sudo apt install -y pipx
pipx ensurepath

# Install Ansible with pipx (clean global install)
pipx install ansible-core
pipx inject ansible-core pywinrm  # Add Windows automation support

# Or fallback to pip if preferred
# pip install --user ansible ansible-core pywinrm
```

### Verify Installation
```bash
# 🐧 Run in WSL2 Ubuntu terminal
ansible --version
ansible-playbook --version
```

## 🚀 Usage

### 1. Complete Automated Setup (Recommended)
```bash
# 🐧 Run in WSL2 Ubuntu terminal
cd /path/to/workstation-setup
ansible-playbook -i inventory/local-dev.ini site.yml
```
**What it does**: Automates Windows + WSL2 setup, provides guidance for manual steps when needed

### 2. Comprehensive Validation
```bash
# 🐧 Run in WSL2 Ubuntu terminal
ansible-playbook -i inventory/local-dev.ini validate-all.yml
```
**Expected results**: All services accessible via HTTPS, registry functional

### 3. Complete Environment Reset
```bash
# 🐧 Run in WSL2 Ubuntu terminal
ansible-playbook -i inventory/local-dev.ini teardown.yml
```
**What it does**: Removes all services, optionally cleans certificates, provides rebuild guidance

### 4. Corporate/Non-Admin Setup
```bash
# 🐧 Run in WSL2 Ubuntu terminal (after manual hosts file update)
ansible-playbook -i inventory/local-dev.ini site.yml --skip-tags "admin-required"
```
**When to use**: When you don't have local admin rights but completed manual prerequisites

### Individual Components (Advanced)
```bash
# Run specific parts
ansible-playbook -i inventory/local-dev.ini validate-windows.yml
ansible-playbook -i inventory/local-dev.ini setup-wsl2.yml
```

## 📊 Automation Coverage

### ✅ Fully Automated
- **Certificate generation** (mkcert)
- **Certificate copying** to WSL2
- **Docker service setup** (Traefik + Registry)
- **Service validation** and testing
- **WSL2 package installation**

### ⚠️ Graceful Admin Attempts
- **Windows hosts file** (attempts update, provides manual steps if failed)

### 🎯 Non-Admin Friendly (Works Automatically)
- **Scoop installation** (no admin required)
- **mkcert installation** (via Scoop, no admin required)
- **Local CA installation** (`mkcert -install`, no admin required)
- **Certificate generation** (works with user-level CA)
- **Docker Desktop settings** (user can configure GUI settings)

## 🎭 Permission Detection

The playbooks automatically detect:
- **Admin privileges** on Windows
- **Sudo access** in WSL2
- **Docker Desktop** integration status
- **Existing tool** installations

## 📋 Manual Steps (When Required)

**Good news: Only ONE step typically requires admin rights!**

### Hosts File Update (ONLY admin-required step)

If Ansible can't update the hosts file, add these entries:

**Option A: PowerShell (Admin session)**
```powershell
# 🪟 Run in Windows PowerShell as Administrator
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 registry.localhost"
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 traefik.localhost"
```

**Option B: Manual Edit (Admin session)**
```
# 🪟 Windows GUI (as Administrator)
1. Open notepad as Administrator
2. Open C:\Windows\System32\drivers\etc\hosts
3. Add the two lines above
4. Save the file
```

**Option C: Corporate Host Management Tool**
Add these entries via your organization's host management tool:
- `127.0.0.1 registry.localhost`
- `127.0.0.1 traefik.localhost`

### Everything Else is Automated!
- ✅ Scoop, mkcert, certificates: Handled automatically
- ✅ Docker Desktop settings: User can configure via GUI (no admin needed)
- ✅ All services: Deployed and validated automatically

## 🧪 Validation

After setup (manual + automated), run validation:
```bash
ansible-playbook -i inventory/local-dev.ini validate-all.yml
```

**Expected Results:**
- ✅ `https://registry.localhost/v2/_catalog` returns repositories
- ✅ `https://traefik.localhost/api/http/services` returns services
- ✅ Certificate validation passes
- ✅ Docker push/pull to registry works

## 🔄 Teardown and Rebuild

```bash
# Clean teardown
ansible-playbook -i inventory/local-dev.ini teardown.yml

# Full rebuild
ansible-playbook -i inventory/local-dev.ini site.yml
```

## 📁 Structure

```
ansible/
├── site.yml                    # Main orchestration playbook
├── validate-windows.yml        # Windows validation and setup
├── setup-wsl2.yml             # WSL2 setup and services
├── validate-all.yml           # End-to-end validation
├── teardown.yml               # Clean teardown
├── group_vars/all.yml         # Configuration variables
├── inventory/local-dev.ini    # Local development inventory
└── roles/
    ├── admin_detector/        # Detect admin privileges
    ├── mkcert_manager/        # Certificate management
    ├── docker_services/       # Traefik + Registry
    └── platform_validator/    # End-to-end testing
```

## 🐛 Troubleshooting

### Common Issues

**"Access Denied" on Windows:**
- Expected for non-admin users
- Follow manual steps in warnings
- Re-run with `--check` to validate

**"Docker not found in WSL2":**
- Enable Docker Desktop WSL2 integration
- Restart WSL2: `wsl --shutdown` then reopen

**"Certificate errors":**
- Ensure mkcert CA is installed: `mkcert -install`
- Check certificates exist: `ls ~/.local/share/certs/`

**"Services not accessible":**
- Verify hosts file entries
- Check Docker containers: `docker ps`
- Validate certificates: `openssl x509 -in ~/.local/share/certs/dev-localhost-wild.crt -text -noout`

## 🔧 Customization

### Variables (group_vars/all.yml)
```yaml
# Domains to set up
local_domains:
  - registry.localhost
  - traefik.localhost

# Certificate configuration
cert_dir: "{{ ansible_env.HOME }}/.local/share/certs"

# Docker services
traefik_version: "v3.0"
registry_version: "2"
```

### Tags for Selective Execution
```bash
# Skip admin-required tasks
--skip-tags "admin-required"

# Run only validation
--tags "validation"

# Run only certificate tasks
--tags "certificates"
```

---

*This automation follows the graceful degradation principle: try to do everything, but provide clear guidance when manual intervention is required.*