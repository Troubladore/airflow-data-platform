# Getting Started - Platform Setup

Set up the Airflow Data Platform enhancement services that work alongside Astronomer.

## 🎯 What This Does

The platform provides **2 enhancement services** that work alongside Astronomer for enterprise teams:

1. **Kerberos Ticket Sharer** - Enables SQL Server Windows Authentication without passwords
2. **SQLModel Framework** - Provides consistent data patterns across teams

These services run locally alongside your Astronomer projects.

**Note:** Docker caches images automatically - no local registry service needed!

## 📋 Prerequisites

<details>
<summary>Click to expand prerequisites</summary>

### Required Software

```bash
# Check what you have
docker --version     # Docker Desktop or Engine
python3 --version    # Python 3.8+
```

### If Missing

**Docker**: Download [Docker Desktop](https://docker.com/products/docker-desktop)
**Python**: Use your system package manager or [python.org](https://python.org)

</details>

## 🚀 Setup Platform Services

Start the 3 enhancement services mentioned above:

```bash
# 1. Clone the platform repository
git clone https://github.com/Troubladore/airflow-data-platform.git
cd airflow-data-platform

# 2. Configure for your organization (optional)
cd platform-bootstrap
cp .env.example .env
# Edit .env to match your Kerberos ticket location if needed

# 3. Start the platform services
make platform-start

# You should see:
# ✓ Ticket sharer started (if Kerberos tickets detected)
# ✓ SQLModel framework available for import
# ✓ Docker caches images automatically (no registry service needed)
```

## ✅ Verify Services

Confirm the platform services are running correctly:

```bash
# Check Kerberos tickets (only if using SQL Server)
klist
# Expected: Your domain tickets (if configured)

# Note: Docker caches images automatically
docker images
# Shows all cached images (pulled and built)

## 🔧 Daily Workflow

Each day when you start development, you'll need these platform services running so your Astronomer projects can access the registry cache and Kerberos tickets:

```bash
# Morning - If using SQL Server, get your Kerberos ticket first
kinit your.username@COMPANY.COM  # Only needed for SQL Server access

# Start all platform services (one command does it all!)
cd airflow-data-platform/platform-bootstrap
make platform-start

# This automatically:
# ✅ Detects your Kerberos ticket and shares it with containers
# ✅ Starts mock services for local testing
# ✅ Docker caches images automatically (no registry service needed)

# Work on your Astronomer projects...
# The services enable faster builds and SQL Server auth

# Evening - Stop platform services
make platform-stop
```

**🎯 Key Point**: `make platform-start` handles everything! If you have a Kerberos ticket from `kinit`, it automatically shares it. No extra steps needed.

## 🎯 Next Steps

Now that platform services are running, explore how to use them:

1. **[Hello World Example](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/hello-world/README.md)**
   Simple Astronomer project using the platform (5 minutes)

2. **Learn the Patterns**
   - [SQLModel Patterns](patterns/sqlmodel-patterns.md) - Consistent data models
   - [Runtime Patterns](patterns/runtime-patterns.md) - Team dependency isolation

3. **Advanced Setup** (if needed)
   - [Kerberos Setup for WSL2](kerberos-setup-wsl2.md) - One-time setup for SQL Server authentication

## 🛑 Stop Services

When you're done for the day:

```bash
cd platform-bootstrap
make platform-stop
```

## 🚨 Troubleshooting

<details>
<summary>Click to expand troubleshooting</summary>

### Images not pulling
```bash
# Check Docker is running
docker info

# Test image pull
docker pull hello-world
# Should pull and cache automatically
```

### Kerberos tickets not working
- Ensure you have valid tickets: `kinit YOUR_USERNAME@DOMAIN.COM`
- Check tickets are in the right location: `ls ~/.krb5_cache/`
- See [Kerberos Setup Guide](kerberos-setup-wsl2.md) for detailed setup

### Services won't start
- Check Docker is running: `docker info`
- Check port conflicts: `lsof -i :5000`
- Review logs: `docker-compose logs`

</details>

---

**Ready to build?** Head to the [Hello World Example](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/hello-world/README.md) to create your first Astronomer project with platform enhancements.
