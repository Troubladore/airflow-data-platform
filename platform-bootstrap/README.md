# Platform Bootstrap - Service Orchestrator

Orchestrates composable platform services for local development.

## 🎯 Composable Architecture

Each service is **standalone and independent** (following the Pagila pattern):

- **../openmetadata/** - Metadata catalog (PostgreSQL + Elasticsearch + OpenMetadata)
- **../kerberos/** - Kerberos ticket sharing for SQL Server auth
- **../pagila/** - PostgreSQL sample database for testing

## 🚀 Quick Start

### Configuration (.env)

```bash
cp .env.example .env
# Edit .env to enable/disable services:
ENABLE_KERBEROS=false       # Set true if you need SQL Server auth
ENABLE_OPENMETADATA=true    # Metadata catalog
```

### Start Platform

```bash
cd platform-bootstrap
make platform-start    # Starts services configured in .env
```

**Examples:**
- Local testing (no domain): `ENABLE_KERBEROS=false, ENABLE_OPENMETADATA=true`
- Full platform: `ENABLE_KERBEROS=true, ENABLE_OPENMETADATA=true`

Note: Docker caches images automatically - no local registry service needed!

## 🚀 Quick Start (10 minutes)

### Option 1: Guided Setup (Recommended for First-Time Users)

Use the interactive setup wizard:

```bash
cd platform-bootstrap
make kerberos-setup

# The wizard will:
# ✓ Check all prerequisites
# ✓ Help you get Kerberos tickets
# ✓ Auto-detect and configure everything
# ✓ Test the complete setup
# Takes 10-15 minutes, fully guided!
```

See [KERBEROS-SETUP-WIZARD.md](./KERBEROS-SETUP-WIZARD.md) for complete wizard documentation.

### Option 2: Manual Setup (For Experienced Users)

If you've done this before:

```bash
# Step 1: Prerequisites (one-time)
docker --version           # Docker Desktop
astro version              # Astronomer CLI
klist                      # Kerberos ticket

# Step 2: Start platform services
cd platform-bootstrap
make platform-start

# This starts:
# - Ticket sharer (uses your existing Kerberos ticket)
# - Mock services (for local development)
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

## 📦 Image Caching

Docker automatically caches all pulled images:

```bash
# First time (online): Images pulled and cached by Docker
astro dev start

# Later (offline): Images served from Docker's cache
astro dev start  # Works offline after initial pull!
```

## 🏗️ What's Actually Running

Just two lightweight services:

1. **Ticket Sharer** (alpine container)
   - Copies your WSL2 Kerberos ticket every 5 minutes
   - Mounts to containers that need it

2. **Mock Services** (optional)
   - Mock Delinea for local development
   - Other mock services as needed

That's it! No complex infrastructure.

Note: Docker caches images automatically - no registry service needed.

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

### Need Help Getting Started?

```bash
# Interactive setup wizard (guides you through everything)
make kerberos-setup

# Diagnose configuration issues
make kerberos-diagnose

# Test ticket sharing
make test-kerberos-simple
```

### No Kerberos ticket found

```bash
# Just get one the normal way
kinit USERNAME@COMPANY.COM

# Or run the wizard for guided help
make kerberos-setup
```

### Can't connect to SQL Server

```bash
# Check your ticket
klist

# Run diagnostic tool
make kerberos-diagnose

# Test basic ticket sharing
make test-kerberos-simple

# Test SQL Server connection
make test-kerberos-full
```

## 📚 Documentation

- **[Quick Start Guide](./KERBEROS-QUICK-START.md)** - One-page command reference
- **[Setup Wizard Guide](./KERBEROS-SETUP-WIZARD.md)** - Complete wizard documentation
- **[Getting Started](../docs/getting-started-simple.md)** - Overall platform setup
- **[Kerberos Diagnostic Guide](../docs/kerberos-diagnostic-guide.md)** - Troubleshooting

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
