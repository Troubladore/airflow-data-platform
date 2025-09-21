# Platform Setup

Complete setup guide for testing and developing with the Airflow Data Platform.

## What You'll Have When Done

After completing this setup, your workstation will have:

- **Local HTTPS services** - `https://traefik.localhost` and `https://registry.localhost` working without certificate errors
- **Docker registry** - Push/pull custom images locally for development and testing
- **Reverse proxy** - Traefik handling routing and TLS termination for all services
- **Development certificates** - Trusted CA and certificates for secure local development

**This is initial platform setup.** The platform evolves with new versions and images over time. See the issue tracker for maintenance/update workflows as they become available.

---

## Step 1: Install Dependencies

**What you're doing:** Installing Ansible automation tools to manage the platform setup across Windows and WSL2.

```bash
# 🐧 WSL2 Ubuntu terminal
sudo apt update && sudo apt install -y pipx
pipx ensurepath

cd /path/to/your/airflow-data-platform
./scripts/install-pipx-deps.sh
ansible-galaxy install -r ansible/requirements.yml
```

**Why Ansible?** Cross-platform automation handles certificates, networking, and Docker setup consistently. See [technical-reference.md](technical-reference.md) for architecture details.

---

## Step 2: Run Platform Setup

**What you're doing:** Deploying Traefik reverse proxy, Docker registry, and development certificates for local HTTPS services.

```bash
# 🐧 WSL2 Ubuntu terminal
ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml --ask-become-pass
```

**Note:** The playbook will detect if you have passwordless sudo configured. If not, you'll be prompted for your password as needed.

**What gets installed:** Local Docker registry, Traefik proxy, mkcert certificates, and host file entries for `*.localhost` domains.

---

## Step 3: Validate Setup

**What you're doing:** Testing that all services are running and accessible with proper HTTPS certificates.

```bash
# 🐧 WSL2 Ubuntu terminal
ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-all.yml --ask-become-pass
```

**Success means these work without certificate errors:**
- ✅ `https://traefik.localhost` - Traefik dashboard
- ✅ `https://registry.localhost/v2/_catalog` - Docker registry API

---

## Step 4: Run Unit Tests

**What you're doing:** Validating that the SQLModel framework works correctly with your platform setup.

```bash
# 🐧 WSL2 Ubuntu terminal
./scripts/test-with-postgres-sandbox.sh
```

**What this tests:**
- SQLModel framework core functionality (table mixins, triggers)
- Database connectivity and schema deployment
- Platform integration with real PostgreSQL database

**Expected result:** All tests pass (approximately 22 tests across multiple test suites).

---

## Setup Complete! 🎉

Your local development environment is ready. The platform includes:
- **Traefik proxy** for routing HTTPS traffic
- **Docker registry** for custom images
- **Development certificates** for secure local connections

## 🚀 Next Steps

Your platform foundation is ready! Now you can:

**Build data solutions** → **[Airflow Data Platform Examples](https://github.com/Troubladore/airflow-data-platform-examples)**

The examples repository contains business implementations, tutorials, and patterns that build on this platform foundation. It shows you how to:
- Create data processing workflows
- Use the SQLModel framework for table definitions
- Deploy datakits to your local environment
- Implement real data engineering patterns

**Platform setup is complete - time to build something awesome!** 🎉

---

<details>
<summary><strong>🧪 Iterative Testing Workflow</strong></summary>

For repeated testing and development cycles:

**Clean environment between tests:**
```bash
./scripts/teardown.sh    # Choose option 1 (keeps certificates for speed)
# Make your changes
ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml --ask-become-pass
```

**Quick validation after changes:**
```bash
curl -k https://registry.localhost/v2/_catalog
curl -k https://traefik.localhost/api/http/services
```

**Component-specific teardown:**
```bash
./scripts/teardown-layer2.sh          # Layer 2 components only
./layer3-warehouses/scripts/teardown-layer3.sh  # Layer 3 components only
```
</details>

<details>
<summary><strong>🚨 Troubleshooting</strong></summary>

**"Permission Denied" on Windows tasks**
- Expected for non-admin users
- Manually add to `C:\Windows\System32\drivers\etc\hosts`:
  ```
  127.0.0.1 registry.localhost
  127.0.0.1 traefik.localhost
  ```

**"Docker not found in WSL2"**
- Enable Docker Desktop WSL2 integration: Settings → Resources → WSL Integration
- Restart WSL2: `wsl --shutdown` then reopen terminal

**"Certificate errors" or HTTPS warnings**
- Run `mkcert -install` to trust the local CA
- Check certificates exist: `ls ~/.local/share/certs/`
- Verify hosts file has the required entries

**Services not responding**
- Check containers are running: `docker ps`
- View detailed logs:
  ```bash
  docker compose -f ~/platform-services/traefik/docker-compose.yml logs -f
  ```
- Test manual connectivity:
  ```bash
  curl -k https://registry.localhost/v2/_catalog
  curl -k https://traefik.localhost/api/http/services
  ```
</details>

<details>
<summary><strong>🏢 Corporate/Non-Admin Environments</strong></summary>

**What works automatically (no admin needed):**
- Install Scoop package manager
- Install mkcert via Scoop
- Generate and install development certificates
- Deploy all Docker services

**What requires admin (or corporate tools):**
- Updating Windows hosts file

**If Ansible can't update hosts file:**
1. Use your organization's host management tool, OR
2. Manually add as Administrator:
   ```
   127.0.0.1 registry.localhost
   127.0.0.1 traefik.localhost
   ```
3. Re-run validation: `ansible-playbook -i ansible/inventory/local-dev.ini ansible/validate-all.yml --ask-become-pass`

**Tip:** To avoid password prompts entirely, set up passwordless sudo:
```bash
sudo visudo  # Add this line: your_username ALL=(ALL) NOPASSWD:ALL
```
</details>
