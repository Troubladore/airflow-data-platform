# Platform Bootstrap for Developers

Minimal setup to get developers productive with Astronomer + enterprise requirements.

## 🎯 What This Does

1. **Caches Artifactory images locally** (work offline)
2. **Shares your existing Kerberos ticket** (no complex Kerberos setup)
3. **Provides a local registry** (faster builds)
4. **Mocks unavailable services** (Delinea, etc.)

## 🚀 Quick Start (10 minutes)

### Step 1: Prerequisites (One-time)

```bash
# You probably already have these
docker --version           # Docker Desktop
astro version              # Astronomer CLI
klist                      # Kerberos ticket from your corporate login
```

### Step 2: Start Platform Services

```bash
cd platform-bootstrap

# Start the minimal platform services
make platform-start

# This starts:
# - Local registry (caches Artifactory images)
# - Ticket sharer (uses your existing WSL2 Kerberos ticket)
# - That's it! No complex infrastructure
```

### Step 3: Create Your Project

```bash
# Use standard Astronomer CLI
astro dev init my-project

# Start Airflow
cd my-project
astro dev start
```

## 🔐 Kerberos: The Simple Way

**We DON'T run a Kerberos KDC locally!** That would be crazy.

Instead:
1. You login to Windows/WSL2 normally
2. You get a Kerberos ticket automatically (or run `kinit`)
3. Our simple service shares that ticket with Docker containers
4. SQL Server connections work using your real credentials

```bash
# Check you have a ticket (from your normal corporate login)
klist

# If not, get one the normal way
kinit YOUR_USERNAME@COMPANY.COM

# That's it! The platform shares this with containers
```

## 📦 Offline Development

The local registry caches images from Artifactory:

```bash
# First time (online): Images pulled from Artifactory and cached
astro dev start

# Later (offline): Images served from local cache
astro dev start  # Still works on airplane!
```

## 🏗️ What's Actually Running

Just two lightweight services:

1. **Registry Cache** (registry:2)
   - Proxies to Artifactory when online
   - Serves from cache when offline

2. **Ticket Sharer** (alpine container)
   - Copies your WSL2 Kerberos ticket every 5 minutes
   - Mounts to containers that need it

That's it! No complex infrastructure.

## 📊 Architecture

```
Your WSL2 Kerberos Ticket (from normal login)
            ↓
    Ticket Sharer (simple copy)
            ↓
    Shared Volume (/shared-ticket)
            ↓
    Your Containers (Airflow, Datakits)
            ↓
    SQL Server (using your real credentials)
```

## ❓ FAQ

### "Do I need to install a KDC?"
**No!** We use your existing corporate Kerberos from Windows/WSL2.

### "Do I need to configure Kerberos?"
**No!** Your IT already did that. We just use what's there.

### "What about Delinea?"
For local dev, we mock it. Real Delinea only in int/qa/prod.

### "Can I work offline?"
**Yes!** The registry caches images. Just need to be online once first.

### "What if I don't have a Kerberos ticket?"
For local dev, you can use SQL auth or mock data. Kerberos only needed for real SQL Servers.

## 🛠️ Troubleshooting

### No Kerberos ticket found

```bash
# Just get one the normal way
kinit USERNAME@COMPANY.COM

# Or use mock data for local development
export USE_MOCK_DATA=true
```

### Registry not caching

```bash
# Check it's running
docker ps | grep registry-cache

# Restart if needed
make registry-start
```

### Can't connect to SQL Server

```bash
# Check your ticket
klist

# Make sure ticket sharer is running
docker ps | grep ticket-refresher
```

## 🎯 Key Point

**This is intentionally minimal!**

We're not trying to replicate corporate infrastructure locally. We're just:
- Caching images for speed/offline work
- Sharing existing Kerberos tickets
- Mocking what's not available locally

Everything else comes from Astronomer out-of-the-box.

## 📋 What Developers Actually Do

```bash
# Monday morning
make platform-start        # Start minimal services (30 seconds)
cd my-project
astro dev start           # Start Airflow (2 minutes)

# Develop all day...

# Friday evening
astro dev stop            # Stop Airflow
make platform-stop        # Stop services

# That's it!
```

No complex Kerberos setup. No infrastructure management. Just develop.
