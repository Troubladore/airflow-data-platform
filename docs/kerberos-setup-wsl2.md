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

### B. Start Our Ticket Sharer

```bash
# Go to platform bootstrap
cd airflow-data-platform/platform-bootstrap

# Start the ticket sharer
docker-compose -f developer-kerberos-simple.yml up -d

# This will:
# 1. Mount your ~/.krb5_cache directory
# 2. Copy tickets to a Docker volume
# 3. Refresh every 5 minutes
```

## 🧪 Step 5: Hello World, Kerberos Style!

Let's test with a real SQL Server connection:

### A. Create Test Script

```python
# test_kerberos.py
import pyodbc
import os

# Your connection details (ask your DBA)
SERVER = 'sqlserver.company.com'
DATABASE = 'TestDB'

# Build connection string for Kerberos
conn_str = (
    f'DRIVER={{ODBC Driver 17 for SQL Server}};'
    f'SERVER={SERVER};'
    f'DATABASE={DATABASE};'
    f'Trusted_Connection=yes;'
    f'Authentication=Kerberos;'
)

print(f"Attempting to connect to {SERVER}...")

try:
    # This will use your Kerberos ticket
    conn = pyodbc.connect(conn_str)
    cursor = conn.cursor()

    # Simple test query
    cursor.execute("SELECT @@VERSION")
    row = cursor.fetchone()

    print("✅ SUCCESS! Connected via Kerberos!")
    print(f"SQL Server Version: {row[0][:50]}...")

    cursor.close()
    conn.close()

except Exception as e:
    print(f"❌ Failed: {e}")
    print("\nTroubleshooting:")
    print("1. Check klist - do you have a valid ticket?")
    print("2. Can you ping the SQL Server?")
    print("3. Is your krb5.conf correct?")
```

### B. Run Test in Docker Container

```bash
# Run test using our runtime environment
docker run --rm \
  --network platform_network \
  -v kerberos_ticket:/krb5/cache:ro \
  -v $(pwd)/test_kerberos.py:/app/test_kerberos.py \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  runtime-environments/python-transform:latest \
  python /app/test_kerberos.py
```

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
