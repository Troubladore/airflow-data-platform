# Getting Started - Platform Setup

Set up the Airflow Data Platform enhancement services that work alongside Astronomer.

## 🎯 What This Does

Provides optional enterprise enhancements for Astronomer:
- **Registry cache** for offline development
- **Kerberos ticket sharing** for SQL Server authentication (WSL2)
- **SQLModel framework** for enterprise data patterns

## 📋 Prerequisites

```bash
# Check what you have
docker --version     # Docker Desktop or Engine
python3 --version    # Python 3.8+
```

### Missing something?

**Docker**: Download [Docker Desktop](https://docker.com/products/docker-desktop)
**Python**: Use your system package manager or [python.org](https://python.org)

## 🚀 Setup Platform Services

```bash
# 1. Clone the platform repository
git clone https://github.com/Troubladore/airflow-data-platform.git
cd airflow-data-platform

# 2. Start platform enhancement services
cd platform-bootstrap
make start

# You should see:
# ✓ Registry cache started at localhost:5000
# ✓ Ticket sharer started (if Kerberos tickets detected)
```

## ✅ Verify Services

```bash
# Check registry cache
curl http://localhost:5000/v2/_catalog
# Should return: {"repositories":[]}

# Check Kerberos tickets (if using SQL Server)
klist
# Should show your domain tickets if configured
```

## 🛑 Stop Services

```bash
cd platform-bootstrap
make stop
```

## 🎯 Next Steps

Now that platform services are running, you're ready to:

### 1. **Try Hello World Example**
```bash
git clone https://github.com/Troubladore/airflow-data-platform-examples.git
cd airflow-data-platform-examples/hello-world
# Follow the README there
```

### 2. **Learn the Patterns**
- [SQLModel Patterns](patterns/sqlmodel-patterns.md) - Data engineering patterns
- [Runtime Patterns](patterns/runtime-patterns.md) - Dependency isolation

### 3. **Set Up Kerberos** (if needed for SQL Server)
- [Kerberos Setup for WSL2](kerberos-setup-wsl2.md) - Complete guide

## 🔧 Daily Workflow

```bash
# Morning
cd airflow-data-platform/platform-bootstrap
make start

# Work on your Astronomer projects...
# (See examples repo for project templates)

# Evening
make stop
```

## 🚨 Troubleshooting

### Registry cache not responding
```bash
docker ps | grep registry
# Should show the registry container running
# If not, check Docker is running
```

### Kerberos tickets not working
- Ensure you have valid tickets: `kinit YOUR_USERNAME@DOMAIN.COM`
- Check tickets are in the right location: `ls ~/.krb5_cache/`
- See [Kerberos Setup Guide](kerberos-setup-wsl2.md)

---

**That's it!** The platform services are now available for any Astronomer project.

For actual project examples and DAG patterns, visit the [examples repository](https://github.com/Troubladore/airflow-data-platform-examples).
