# Platform Setup Guide

**🎯 Quick Start for the Astronomer Airflow Data Engineering Platform**

This guide provides clear workflows for setting up your development environment from scratch. Choose the method that fits your environment and permissions.

## 🚀 Recommended Setup (Ansible Automation)

**Best choice: Handles both admin and non-admin environments gracefully**

### Prerequisites
```bash
# Install Ansible in WSL2
pip install ansible ansible-core pywinrm
```

### Complete Setup
```bash
# Clone and navigate to repository
cd /path/to/workstation-setup

# Run comprehensive setup (tries admin tasks, provides guidance when needed)
ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml
```

### Validation
```bash
# Verify everything works
ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-all.yml
```

**Expected Results:**
- ✅ `https://traefik.localhost` - Traefik dashboard
- ✅ `https://registry.localhost/v2/_catalog` - Container registry
- ✅ Docker push/pull operations work

---

## 🔄 Testing & Development Workflow

### Complete Environment Reset
```bash
# Clean teardown everything
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
# Test specific components
ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-all.yml

# Or manually test key endpoints
curl -k https://registry.localhost/v2/_catalog
curl -k https://traefik.localhost/api/http/services
```

---

## 🪟 Corporate/Non-Admin Environment Setup

**For environments where you don't have local admin rights**

### Manual Prerequisites (One-time setup)
You'll need to request these from your IT team or use approved tools:

1. **Install mkcert** (via approved software center)
2. **Install local CA**: Run `mkcert -install`
3. **Update hosts file** (via corporate host management tool):
   ```
   127.0.0.1 registry.localhost
   127.0.0.1 traefik.localhost
   ```
4. **Enable Docker Desktop WSL2 integration**

### Automated Setup (After manual prerequisites)
```bash
# Skip admin-required tasks
ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml --skip-tags "admin-required"

# Ansible will validate manual steps were completed correctly
```

---

## 🛠️ Legacy/Manual Setup

**If Ansible is not available or preferred**

```bash
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
ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-all.yml

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