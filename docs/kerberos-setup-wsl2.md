# Kerberos Setup for WSL2 - Complete Guide

Getting Kerberos working in WSL2 for SQL Server authentication. This guide holds your hand through every step.

## 🎯 What We're Solving

You need to connect to SQL Server databases that require Windows Authentication (Kerberos/NTLM) from Docker containers running in WSL2. This is notoriously tricky.

## 📋 Prerequisites Check

First, let's see what you have:

```bash
# In WSL2 Ubuntu terminal
# Check if you have Kerberos installed
which kinit
which klist

# If not found, install it:
sudo apt-get update
sudo apt-get install -y krb5-user libkrb5-dev
```

## 🔐 Step 1: Understanding Your Environment

### What's Happening Behind the Scenes

```
Windows Domain (COMPANY.COM)
         ↓
   Your Windows Login
         ↓
      WSL2 Ubuntu
         ↓
   Docker Containers
         ↓
    SQL Server
```

Your Windows credentials need to flow through all these layers!

## 🛠️ Step 2: Configure Kerberos in WSL2

### A. Get Your Company's Kerberos Config

```bash
# Your IT team should have a krb5.conf file
# It usually looks like this:

cat > /tmp/krb5.conf << 'EOF'
[libdefaults]
    default_realm = COMPANY.COM
    dns_lookup_realm = false
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true

[realms]
    COMPANY.COM = {
        kdc = dc01.company.com
        kdc = dc02.company.com
        admin_server = dc01.company.com
    }

[domain_realm]
    .company.com = COMPANY.COM
    company.com = COMPANY.COM
EOF

# Replace COMPANY.COM with your actual domain
# Ask IT for the actual KDC servers
```

### B. Install the Config

```bash
# Copy to the right location
sudo cp /tmp/krb5.conf /etc/krb5.conf

# Verify it's there
cat /etc/krb5.conf
```

## 🎫 Step 3: Get Your First Kerberos Ticket

### A. Test with Your Windows Credentials

```bash
# Replace USERNAME with your actual Windows username
# Replace COMPANY.COM with your actual domain (must be UPPERCASE)
kinit USERNAME@COMPANY.COM

# You'll be prompted for your Windows password
# Enter it (nothing will appear as you type - that's normal)
```

### B. Verify You Have a Ticket

```bash
# List your tickets
klist

# You should see something like:
# Ticket cache: FILE:/tmp/krb5cc_1000
# Default principal: USERNAME@COMPANY.COM
#
# Valid starting     Expires            Service principal
# 01/24/24 10:00:00  01/24/24 20:00:00  krbtgt/COMPANY.COM@COMPANY.COM
```

**🎉 If you see a ticket, Kerberos is working in WSL2!**

## 🐳 Step 4: Share Ticket with Docker Containers

Now we need to make your ticket available to Docker containers.

### A. Create a Shared Ticket Location

```bash
# Create directory for sharing
mkdir -p ~/.krb5_cache

# Copy your ticket there
cp /tmp/krb5cc_$(id -u) ~/.krb5_cache/krb5cc

# Verify it's there
ls -la ~/.krb5_cache/
```

### B. Ticket Sharing Happens Automatically!

**🎯 Good news**: If you're following the [daily workflow](getting-started-simple.md#-daily-workflow), ticket sharing is automatic!

```bash
# When you run this (after kinit):
cd airflow-data-platform/platform-bootstrap
make platform-start

# It automatically:
# 1. Detects your Kerberos ticket
# 2. Starts the ticket sharer
# 3. Shares tickets with all Docker containers
# 4. Refreshes every 5 minutes
```

**💡 Why automatic?** The `make platform-start` command checks for tickets and starts the sharer if found. No extra steps needed!

<details>
<summary>Advanced: Start only Kerberos service</summary>

If you want to start ONLY the Kerberos ticket sharer (without registry or other services):

```bash
# Start just Kerberos sharing
docker compose -f developer-kerberos-simple.yml up -d

# Use case: When you only need SQL Server access
# and don't need the full platform stack
```

But for most users, `make platform-start` is all you need!
</details>

## 🧪 Step 5: The Moment of Truth - Test SQL Server Connection!

**🎯 Why we're here**: This is where all your setup pays off. We'll verify that Docker containers can use your Kerberos ticket to connect to SQL Server - proving the entire authentication chain works!

### A. We've Included a Test Script

Good news - we've already created a test script for you:

```bash
# The test script is in platform-bootstrap
cd airflow-data-platform/platform-bootstrap
ls test_kerberos.py  # It's already there!

# Quick look at what it does
head -20 test_kerberos.py
```

The script will:
- ✓ Check for Kerberos tickets in the container
- ✓ Attempt SQL Server connection using your ticket
- ✓ Provide helpful troubleshooting if something's wrong

### B. Run the Test (This Will Actually Work!)

```bash
# Make sure you're in platform-bootstrap directory
cd airflow-data-platform/platform-bootstrap

# OPTION 1: Simple test (no SQL Server needed)
# Just verify tickets are shared with containers
docker run --rm \
  --network platform_network \
  -v platform_kerberos_cache:/krb5/cache:ro \
  -v $(pwd)/test_kerberos_simple.py:/app/test.py \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  python:3.11-alpine \
  sh -c "apk add --no-cache krb5 && python /app/test.py"

# OPTION 2: Full SQL Server test (requires server access)
# Set your SQL Server details (ask your DBA for these)
export SQL_SERVER="your-sql-server.company.com"  # Replace with your server
export SQL_DATABASE="TestDB"                      # Replace with your database

# Run the SQL Server test
docker run --rm \
  --network platform_network \
  -v platform_kerberos_cache:/krb5/cache:ro \
  -v $(pwd)/test_kerberos.py:/app/test_kerberos.py \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  -e SQL_SERVER="$SQL_SERVER" \
  -e SQL_DATABASE="$SQL_DATABASE" \
  python:3.11-alpine \
  sh -c "apk add --no-cache krb5 gcc musl-dev unixodbc-dev && \
         pip install --no-cache-dir pyodbc && \
         python /app/test_kerberos.py"
```

**💡 Tip**: Start with Option 1 to verify ticket sharing works, then move to Option 2 when you have SQL Server details.

## 🚨 Troubleshooting Guide

### "Cannot find KDC for realm"

```bash
# Your krb5.conf might be wrong
# Test DNS resolution
nslookup dc01.company.com

# If that fails, you might need to add to /etc/hosts
echo "10.1.2.3 dc01.company.com" | sudo tee -a /etc/hosts
```

### "Ticket expired"

```bash
# Tickets expire! Renew with:
kinit -R

# Or get a new one:
kinit USERNAME@COMPANY.COM
```

### "Clock skew too great"

```bash
# Your WSL2 clock is off
# Sync it with:
sudo hwclock -s

# Or install ntp:
sudo apt-get install -y ntp
sudo service ntp restart
```

### "Cannot contact any KDC"

```bash
# Firewall issue or wrong KDC
# Test connectivity:
nc -zv dc01.company.com 88

# Port 88 should be open
# If not, talk to IT
```

## 📝 Daily Workflow

Once it's working, here's your daily routine:

```bash
# Morning: Get fresh ticket
kinit USERNAME@COMPANY.COM

# Check it's valid
klist

# Start platform services
cd airflow-data-platform/platform-bootstrap
make start

# Your containers now have Kerberos access!

# Evening: (tickets auto-expire, no cleanup needed)
```

## 🎯 Integration with Airflow DAGs

Now you can use Kerberos in your DAGs:

```python
from airflow import DAG
from airflow.providers.docker.operators.docker import DockerOperator
from datetime import datetime

dag = DAG(
    'sql_server_kerberos_example',
    start_date=datetime(2024, 1, 1),
    catchup=False
)

# This task will have Kerberos access
extract_task = DockerOperator(
    task_id='extract_from_sql_server',
    image='runtime-environments/python-transform:latest',
    command='python extract_sales_data.py',
    volumes=[
        'kerberos_ticket:/krb5/cache:ro',  # Mount the ticket
    ],
    environment={
        'KRB5CCNAME': '/krb5/cache/krb5cc',  # Tell it where
        'SOURCE_SERVER': 'sqlserver.company.com',
        'SOURCE_DB': 'SalesDB'
    },
    network_mode='bridge',
    dag=dag
)
```

## ✅ Success Checklist

- [ ] Kerberos installed in WSL2
- [ ] `/etc/krb5.conf` configured with your domain
- [ ] Can get ticket with `kinit`
- [ ] Ticket visible with `klist`
- [ ] Ticket sharer running in Docker
- [ ] Test script connects to SQL Server
- [ ] Can use in Airflow DAGs

## 🆘 Still Stuck?

Common helpers:

```bash
# Debug Kerberos issues
export KRB5_TRACE=/dev/stdout
kinit USERNAME@COMPANY.COM

# Check what SQL Server is expecting
tsql -S sqlserver.company.com -U USERNAME

# Test with sqlcmd (if available)
sqlcmd -S sqlserver.company.com -E
```

Remember: Kerberos is picky about:
- Domain names must be UPPERCASE (COMPANY.COM not company.com)
- Time sync must be within 5 minutes
- DNS must resolve correctly
- Tickets expire and need renewal

---

**Once this works, you've conquered one of the hardest parts of enterprise data engineering!** 🎉
