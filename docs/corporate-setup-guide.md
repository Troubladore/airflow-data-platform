# Corporate Environment Setup Guide

## Problem

Your organization blocks Docker Hub (`registry-1.docker.io`). You need to configure everything to use corporate Artifactory instead.

## One-Time Docker Configuration

### Step 1: Docker Login

```bash
docker login artifactory.yourcompany.com
# Username: your_ldap_username
# Password: your_artifactory_token
```

Credentials stored securely in `~/.docker/config.json`.

### Step 2: Configure Docker to Use Artifactory Mirror

**Option A: Docker Desktop (Windows/Mac)**
1. Open Docker Desktop
2. Settings → Docker Engine
3. Add to JSON config:
```json
{
  "registry-mirrors": ["https://artifactory.yourcompany.com/docker-remote"]
}
```
4. Apply & Restart

**Option B: Docker Daemon (Linux)**
```bash
sudo nano /etc/docker/daemon.json
```
Add:
```json
{
  "registry-mirrors": ["https://artifactory.yourcompany.com/docker-remote"]
}
```
```bash
sudo systemctl restart docker
```

## Platform Configuration (platform-config.yaml)

### Step 1: Run the Setup Wizard

```bash
./platform setup
```

The wizard will:
- Prompt you for corporate-specific settings (Kerberos domain, Artifactory paths, etc.)
- Generate `platform-config.yaml` with your configuration
- Auto-generate `.env` from the YAML configuration

Edit `platform-config.yaml` as needed for your corporate environment.

### Step 2: Configure Corporate Image Paths

Ask your DevOps team for exact paths, then edit `platform-config.yaml`:

```yaml
kerberos:
  domain: YOURCOMPANY.COM
  cache:
    type: DIR
    path: ${HOME}/.krb5-cache
    ticket: dev

images:
  alpine: artifactory.yourcompany.com/docker-remote/library/alpine:3.19
  python: artifactory.yourcompany.com/docker-remote/library/python:3.11-slim
  astronomer: artifactory.yourcompany.com/docker-remote/astronomer/ap-airflow:11.10.0

# ODBC Drivers (if mirrored)
# odbc:
#   driver_url: https://artifactory.yourcompany.com/microsoft-binaries/odbc/v18.3
```

The platform will auto-generate `.env` from this configuration when you run `./platform setup` or other platform commands.

### Step 3: IMPORTANT - Configuration File Guidance

**platform-config.yaml** contains YOUR corporate paths and settings:
- You MAY commit it to your corporate fork if sharing config with your team
- OR keep it local if settings are personal/sensitive

**.env is auto-generated** and should NEVER be committed:
- Auto-generated from platform-config.yaml
- Regenerated on each platform command

`.gitignore` includes:
- `.env` (auto-generated, never commit)
- `**/.secrets/` (sensitive credentials)

This ensures auto-generated files and secrets never get committed.

## Preserving Config When Merging Upstream

### Your Workflow (Corporate Fork)

```bash
# 1. Your fork setup (one-time)
git remote add upstream https://github.com/Troubladore/airflow-data-platform.git

# 2. Create develop branch with corporate config
git checkout -b develop

# 3. Run setup wizard to create platform-config.yaml
./platform setup
# Answer prompts with corporate-specific values

# 4. Optionally commit platform-config.yaml if sharing with team
git add platform-config.yaml  # Optional: commit if team needs shared config
git commit -m "Add corporate platform configuration"

# .env is auto-generated and in .gitignore, so it WON'T be committed
# This is GOOD - it stays local and regenerates as needed
```

### Merging Upstream Changes

```bash
# Get latest from upstream
git fetch upstream main

# Merge into your develop branch
git checkout develop
git merge upstream/main

# Your platform-config.yaml may need manual merge if you committed it
# Your .env is NOT tracked and auto-regenerates, so no conflicts!
# It regenerates from your platform-config.yaml on next platform command
```

### The Pattern

**Tracked in git (shared with team):**
- `platform-config.yaml` - (Optional) Corporate configuration if you want to share
- All code, docs, scripts

**NOT tracked (auto-generated or personal):**
- `.env` - Auto-generated from platform-config.yaml, never commit
- `.secrets/` - Passwords, tokens
- `docker-compose.override.yml` - Personal overrides

## Testing in Corporate Environment

Now that Artifactory is configured:

```bash
# This will use Artifactory, not Docker Hub
./diagnose-kerberos.sh
# Step 4 will pull alpine from Artifactory
