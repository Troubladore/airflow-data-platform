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

## Platform Configuration (.env)

### Step 1: Create Your Corporate .env

```bash
cd platform-bootstrap
cp .env.example .env
nano .env
```

### Step 2: Set Corporate Image Paths

Ask your DevOps team for exact paths, or use this template:

```bash
# Kerberos (from diagnostic)
COMPANY_DOMAIN=YOURCOMPANY.COM
KERBEROS_CACHE_TYPE=DIR
KERBEROS_CACHE_PATH=${HOME}/.krb5-cache
KERBEROS_CACHE_TICKET=dev

# Corporate Artifactory Image Sources
IMAGE_ALPINE=artifactory.yourcompany.com/docker-remote/library/alpine:3.19
IMAGE_PYTHON=artifactory.yourcompany.com/docker-remote/library/python:3.11-slim
IMAGE_ASTRONOMER=artifactory.yourcompany.com/docker-remote/astronomer/ap-airflow:11.10.0

# ODBC Drivers (if mirrored)
# ODBC_DRIVER_URL=https://artifactory.yourcompany.com/microsoft-binaries/odbc/v18.3
```

### Step 3: IMPORTANT - Never Commit .env!

**The .env file contains YOUR corporate paths** and should stay local.

`.gitignore` now includes:
- `platform-bootstrap/.env`
- `**/.env`
- `**/.secrets/`

This ensures your corporate config never gets committed.

## Preserving Config When Merging Upstream

### Your Workflow (Corporate Fork)

```bash
# 1. Your fork setup (one-time)
git remote add upstream https://github.com/Troubladore/airflow-data-platform.git

# 2. Create develop branch with corporate config
git checkout -b develop
cp platform-bootstrap/.env.example platform-bootstrap/.env
# Edit .env with corporate paths
git add platform-bootstrap/.env  # WAIT - DON'T DO THIS!

# .env is in .gitignore, so it WON'T be committed
# This is GOOD - it stays local only
```

### Merging Upstream Changes

```bash
# Get latest from upstream
git fetch upstream main

# Merge into your develop branch
git checkout develop
git merge upstream/main

# Your .env is NOT tracked, so it won't conflict!
# It stays exactly as you configured it
```

### The Pattern

**Tracked in git (shared with team):**
- `.env.example` - Template with comments
- All code, docs, scripts

**NOT tracked (your personal/corp config):**
- `.env` - Your corporate Artifactory paths
- `.secrets/` - Passwords, tokens
- `docker-compose.override.yml` - Personal overrides

## Testing in Corporate Environment

Now that Artifactory is configured:

```bash
# This will use Artifactory, not Docker Hub
./diagnose-kerberos.sh
# Step 4 will pull alpine from Artifactory
