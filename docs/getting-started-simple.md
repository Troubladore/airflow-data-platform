# Getting Started - Platform Setup

Set up the Airflow Data Platform enhancement services that work alongside Astronomer.

## 🎯 What This Does

The platform provides **3 enhancement services** that make Astronomer better for enterprise teams:

1. **Registry Cache** - Speeds up Docker builds and enables offline development
2. **Kerberos Ticket Sharer** - Enables SQL Server Windows Authentication without passwords
3. **SQLModel Framework** - Provides consistent data patterns across teams

These services run locally alongside your Astronomer projects.

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
# 1. Clone the platform repository (use correct branch)
git clone https://github.com/Troubladore/airflow-data-platform.git
cd airflow-data-platform
# Note: If platform-bootstrap is missing, check you're on the right branch:
# git checkout feature/kerberos-sidecar-implementation

# 2. Start the platform services
cd platform-bootstrap
make platform-start

# You should see:
# ✓ Registry cache started at localhost:5000
# ✓ Ticket sharer started (if Kerberos tickets detected)
# ✓ SQLModel framework available for import
```

## ✅ Verify Services

Confirm the platform services are running correctly:

```bash
# Check registry cache (should return empty JSON)
curl http://localhost:5000/v2/_catalog
# Expected: {"repositories":[]}

# Check Kerberos tickets (only if using SQL Server)
klist
# Expected: Your domain tickets (if configured)
```

## 🔧 Daily Workflow

Each day when you start development, you'll need these platform services running so your Astronomer projects can access the registry cache and Kerberos tickets:

```bash
# Morning - Start platform services
cd airflow-data-platform/platform-bootstrap
make platform-start

# Work on your Astronomer projects...
# The services enable faster builds and SQL Server auth

# Evening - Stop platform services
make platform-stop
```

## 🎯 Next Steps

Now that platform services are running, explore how to use them:

1. **[Hello World Example](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/hello-world/README.md)**
   Simple Astronomer project using the platform (5 minutes)

2. **Learn the Patterns**
   - [SQLModel Patterns](patterns/sqlmodel-patterns.md) - Consistent data models
   - [Runtime Patterns](patterns/runtime-patterns.md) - Team dependency isolation

3. **Advanced Setup** (if needed)
   - [Kerberos Setup for WSL2](kerberos-setup-wsl2.md) - For SQL Server authentication

## 🛑 Stop Services

When you're done for the day:

```bash
cd platform-bootstrap
make platform-stop
```

## 🚨 Troubleshooting

<details>
<summary>Click to expand troubleshooting</summary>

### Registry cache not responding
```bash
docker ps | grep registry
# Should show the registry container running
# If not, check Docker is running
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
