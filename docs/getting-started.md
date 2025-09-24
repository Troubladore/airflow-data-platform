# Platform Setup

Complete setup guide for the Airflow Data Platform with component-based deployment.

## What You'll Have When Done

After completing this setup, your workstation will have:

- **Apache Airflow** - Full workflow orchestration platform at `https://airflow.localhost`
- **Docker Registry** - Private image storage at `https://registry.localhost` with web UI
- **Traefik Proxy** - HTTPS termination and routing for all platform services
- **Development Certificates** - Trusted mkcert CA for `*.localhost` domains without warnings
- **Component Architecture** - Six atomic, idempotent components that can be deployed individually

**Platform Services:**
- `https://airflow.localhost` - Apache Airflow (username: admin, password: admin)
- `https://registry.localhost/v2/` - Docker Registry API
- `https://registry-ui.localhost` - Registry Web UI
- `https://traefik.localhost/dashboard/` - Traefik Dashboard
- `https://whoami.localhost` - Test service for verification

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

## Step 2: Run Platform Setup (Component-Based)

**The setup uses atomic components.** Each component is idempotent and can be run independently or all together.

### Option A: Run All Components at Once

```bash
# 🐧 WSL2 Ubuntu terminal
ansible-playbook -i ansible/inventory/local-dev.ini ansible/orchestrators/setup-simple.yml
```

### Option B: Run Components Individually (Recommended for First Time)

```bash
# Component 1: Install mkcert binary in WSL2
ansible-playbook -i ansible/inventory/local-dev.ini \
  -e "component_only=01-mkcert-binary-tasks.yml" \
  ansible/orchestrators/setup-simple.yml

# Component 2: Windows CA Trust (will prompt for Windows PowerShell steps)
ansible-playbook -i ansible/inventory/local-dev.ini \
  -e "component_only=02-windows-ca-trust-tasks.yml" \
  ansible/orchestrators/setup-simple.yml

# Component 3: Certificate File Management
ansible-playbook -i ansible/inventory/local-dev.ini \
  -e "component_only=03-certificate-file-management-tasks.yml" \
  ansible/orchestrators/setup-simple.yml

# Component 4: Traefik Platform Deployment
ansible-playbook -i ansible/inventory/local-dev.ini \
  -e "component_only=04-traefik-platform-deployment-tasks.yml" \
  ansible/orchestrators/setup-simple.yml

# Component 5: Docker Registry Deployment
ansible-playbook -i ansible/inventory/local-dev.ini \
  -e "component_only=05-docker-registry-deployment-tasks.yml" \
  ansible/orchestrators/setup-simple.yml

# Component 6: Apache Airflow Deployment
ansible-playbook -i ansible/inventory/local-dev.ini \
  -e "component_only=06-airflow-platform-deployment-tasks.yml" \
  ansible/orchestrators/setup-simple.yml
```

**What each component does:**
1. **mkcert Binary** - Installs certificate generation tool
2. **Windows CA Trust** - Installs CA to Windows store (requires PowerShell)
3. **Certificate Management** - Copies certificates from Windows to WSL2
4. **Traefik Platform** - Deploys HTTPS reverse proxy
5. **Docker Registry** - Private image storage with web UI
6. **Apache Airflow** - Workflow orchestration platform

---

## Step 3: Validate Setup

**What you're doing:** Testing that all services are running and accessible with proper HTTPS certificates.

### Quick Browser Test
Open these URLs in your browser - they should all work without certificate warnings:

- ✅ `https://airflow.localhost` - Apache Airflow (login: admin/admin)
- ✅ `https://traefik.localhost/dashboard/` - Traefik dashboard
- ✅ `https://registry-ui.localhost` - Docker Registry UI
- ✅ `https://whoami.localhost` - Test service showing headers

### Command Line Validation

```bash
# 🐧 WSL2 Ubuntu terminal
# Test all HTTPS endpoints
for url in https://traefik.localhost/api/overview \
           https://registry.localhost/v2/ \
           https://registry-ui.localhost/ \
           https://airflow.localhost/health \
           https://whoami.localhost/; do
  echo "Testing $url..."
  curl -s -o /dev/null -w "  Status: %{http_code}\n" "$url"
done
```

**Expected:** All services return HTTP 200 or 401 (for authenticated endpoints)

---

## Step 4: Run Unit Tests

**What you're doing:** Validating that the SQLModel framework works correctly with your platform setup.

```bash
# 🐧 WSL2 Ubuntu terminal
./scripts/test-with-postgres-sandbox.sh
```

**What this tests:**
- SQLModel framework core functionality (table mixins, triggers)
- Database connectivity with real PostgreSQL database
- Deployment utilities with self-contained test fixtures

**Expected result:** All framework tests pass (~24 tests including deployment validation).

---

## Setup Complete! 🎉

Your local development environment is ready with all platform services:

### Platform Services Running
- **Apache Airflow** - Workflow orchestration at `https://airflow.localhost`
- **Docker Registry** - Private image storage at `https://registry.localhost`
- **Registry UI** - Web interface at `https://registry-ui.localhost`
- **Traefik Proxy** - HTTPS routing and dashboard at `https://traefik.localhost`
- **Development Certificates** - Trusted mkcert CA for all `*.localhost` domains

### Component Architecture Benefits
The platform uses 6 atomic, idempotent components that:
- ✅ **Can be run individually** - Debug or update specific parts
- ✅ **Are truly idempotent** - Safe to run multiple times
- ✅ **Check prerequisites** - Each component validates dependencies
- ✅ **Handle Windows/WSL2 boundary** - Certificates generated in Windows, used in WSL2
- ✅ **Provide clear feedback** - Know exactly what each component does

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
- Ensure Component 2 completed successfully (Windows CA trust)
- Check certificates exist: `ls ~/.local/share/certs/`
- Verify certificate domains: `openssl x509 -in ~/.local/share/certs/dev-localhost-wild.crt -text | grep DNS`
- Clear browser cache (especially Brave browser)
- Re-run Component 3 to sync certificates from Windows

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

**Traefik not routing to service (404 errors)**
- Check if router is detected: `curl -s http://localhost:8080/api/http/routers | grep service_name`
- Verify container labels: `docker inspect container_name | grep traefik`
- Check for "too many services" error in Traefik logs: `docker logs traefik | grep ERR`
- Solution: Ensure service names are explicitly defined in labels
- Restart Traefik to clear cache: `docker restart traefik`

**🚨 CRITICAL: Wrong Docker Compose Configuration**
**Symptom**: HTTPS certificate errors when accessing services, registry logs showing "open /certs/cert.pem: no such file or directory"

**Root Cause**: Using static `prerequisites/traefik-registry/docker-compose.yml` instead of Ansible-generated platform services

**Solution**:
1. Stop incorrect services: `docker compose -f /path/to/airflow-data-platform/prerequisites/traefik-registry/docker-compose.yml down`
2. Use proper platform services: `cd ~/platform-services/traefik && docker compose up -d`
3. Verify: `curl -k https://traefik.localhost` should work

**Prevention**: Always use Ansible-generated services (`~/platform-services/traefik/`) which properly mount WSL2 certificates from `~/.local/share/certs/`. The static prerequisite files are templates only.

**🚨 Docker Desktop Proxy Issues**
**Symptom**: Timeout errors when pulling from registry.localhost: "proxyconnect tcp: dial tcp 192.168.65.1:3128: i/o timeout"

**Root Cause**: Docker Desktop has a proxy configured but *.localhost domains aren't in the bypass list

**Solution**:
1. Open Docker Desktop → Settings → Resources → Proxies
2. In "Bypass proxy settings for these hosts & domains" add:
   ```
   localhost,*.localhost,127.0.0.1,registry.localhost,traefik.localhost,airflow.localhost
   ```
3. Click "Apply & restart"
4. Re-run validation

**Note**: This is common in corporate environments or when Docker Desktop auto-detects Windows proxy settings. The platform setup now detects this and prompts you to fix it.
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
