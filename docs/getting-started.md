# Getting Started

Complete setup guide for testing and developing with the Airflow Data Platform.

## Prerequisites

```bash
# 🐧 WSL2 Ubuntu terminal
sudo apt update && sudo apt install -y pipx
pipx ensurepath

cd /path/to/your/airflow-data-platform
./scripts/install-pipx-deps.sh
ansible-galaxy install -r ansible/requirements.yml
```

## Setup

```bash
# 🐧 WSL2 Ubuntu terminal
sudo echo "Testing sudo access"  # Cache password
ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml --ask-become-pass
```

## Validate

```bash
ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-all.yml --ask-become-pass
```

**Success = These work:**
- ✅ `https://traefik.localhost`
- ✅ `https://registry.localhost/v2/_catalog`

## Testing Workflow

**Clean environment between tests:**
```bash
./scripts/teardown.sh    # Choose option 1 (keeps certificates)
# Make your changes
ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml --ask-become-pass
```

**Quick validation after changes:**
```bash
curl -k https://registry.localhost/v2/_catalog
curl -k https://traefik.localhost/api/http/services
```

## Troubleshooting

**"Permission Denied"** → Expected for non-admin. Manually add to `C:\Windows\System32\drivers\etc\hosts`:
```
127.0.0.1 registry.localhost
127.0.0.1 traefik.localhost
```

**"Docker not found"** → Enable Docker Desktop WSL2 integration, restart WSL2

**"Certificate errors"** → Run `mkcert -install`, check `ls ~/.local/share/certs/`

**Services not responding** → Check `docker ps`, view logs with:
```bash
docker compose -f ~/platform-services/traefik/docker-compose.yml logs -f
```

## Corporate/Non-Admin Users

The setup handles everything automatically except the hosts file. If Ansible can't update it:
1. Use your corporate host management tool
2. Or manually add the entries above as Administrator

---

**That's it!** Your platform is ready for testing PR #6. The environment includes Traefik proxy, Docker registry, and all certificates needed for local development.
