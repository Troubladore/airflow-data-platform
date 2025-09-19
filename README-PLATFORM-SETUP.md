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
# Run full automation (will handle everything except hosts file)
ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml

# If hosts file update fails, Ansible will provide clear guidance
# Add entries via your corporate host management tool
# Re-run to validate
ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-all.yml
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