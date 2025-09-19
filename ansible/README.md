# Ansible Platform Setup

Automated setup for the Astronomer Airflow data engineering platform with graceful handling of admin permissions.

## 🎯 Strategy

This automation uses a **"try to fix, fail gracefully"** approach:
- ✅ **Local admin users**: Full automation of all prerequisite steps
- ⚠️ **Non-admin users**: Clear guidance for manual steps with validation

## 📋 Prerequisites

### Install Ansible (WSL2 Only)
```bash
# Install in WSL2 - works for both Windows and WSL2 targets
pip install ansible ansible-core
pip install pywinrm  # For Windows automation
```

### Verify Installation
```bash
ansible --version
ansible-playbook --version
```

## 🚀 Usage

### 1. Complete Automated Setup (Recommended)
```bash
# Run full automation - attempts admin tasks, fails gracefully
ansible-playbook -i inventory/local-dev.ini site.yml
```
**What it does**: Tries everything, provides clear guidance for manual steps when needed

### 2. Comprehensive Validation
```bash
# Verify everything works after setup
ansible-playbook -i inventory/local-dev.ini validate-all.yml
```
**Expected results**: All services accessible via HTTPS, registry functional

### 3. Complete Environment Reset
```bash
# Clean teardown for testing
ansible-playbook -i inventory/local-dev.ini teardown.yml
```
**What it does**: Removes all services, optionally cleans certificates, provides rebuild guidance

### 4. Corporate/Non-Admin Setup
```bash
# Skip admin-required tasks (after manual prerequisites)
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
- **mkcert installation** (tries Scoop, falls back to manual)
- **Windows hosts file** (attempts update, provides manual steps)
- **Docker Desktop settings** (detects and guides user)

## 🎭 Permission Detection

The playbooks automatically detect:
- **Admin privileges** on Windows
- **Sudo access** in WSL2
- **Docker Desktop** integration status
- **Existing tool** installations

## 📋 Manual Steps (When Required)

If you see warnings for manual steps, complete these as local admin:

### 1. Install mkcert (Windows)
```powershell
# Using Scoop (recommended)
scoop install mkcert

# Or download from: https://github.com/FiloSottile/mkcert/releases
```

### 2. Install Local CA
```powershell
mkcert -install
```

### 3. Update Hosts File
**Option A: PowerShell (Admin session)**
```powershell
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 registry.localhost"
Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 traefik.localhost"
```

**Option B: Admin Tool (Corporate environments)**
Add these entries via your organization's host management tool:
- `127.0.0.1 registry.localhost`
- `127.0.0.1 traefik.localhost`

### 4. Docker Desktop WSL2 Integration
1. Open Docker Desktop Settings
2. Go to Resources → WSL Integration
3. Enable integration for your WSL2 distro
4. Apply & Restart

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