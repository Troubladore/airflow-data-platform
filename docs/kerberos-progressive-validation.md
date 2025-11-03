# Kerberos Progressive Validation Guide

**Prerequisites:** You've completed [Getting Started - Platform Setup](getting-started-simple.md) basic configuration.

**Purpose:** This guide walks you through validating your Kerberos setup incrementally, from simple to complex, ensuring each layer works before moving to the next.

**Time:** 15-30 minutes (depending on corporate environment)

---

## Why Progressive Validation?

Testing Kerberos authentication in stages helps you:
- ✅ Identify exactly where issues occur
- ✅ Build confidence that each layer works
- ✅ Understand how components integrate
- ✅ Troubleshoot effectively when things break

**The 5-Step Path:**
1. Configure corporate Kerberos settings
2. Verify credentials are cached in WSL2
3. Test direct SQL Server connection from WSL2
4. Test SQL Server connection from Docker container via sidecar
5. Test end-to-end Airflow DAG execution

---

## Step 1: Configure Corporate Kerberos

### 1.1 Get Information from IT

Contact your corporate IT/Security team for:
- **Kerberos Realm** (e.g., `MYCOMPANY.COM`)
- **KDC Server** (e.g., `kdc.mycompany.com`)
- **SQL Server Hostname** for testing (e.g., `sql-dev.mycompany.com`)
- **Test Database** you have read access to

### 1.2 Configure krb5.conf

**Check if you already have corporate krb5.conf:**
```bash
cat /etc/krb5.conf
```

**If not, create it:**
```bash
sudo nano /etc/krb5.conf
```

**Minimal working configuration:**
```ini
[libdefaults]
    default_realm = MYCOMPANY.COM
    dns_lookup_realm = false
    dns_lookup_kdc = false
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true

[realms]
    MYCOMPANY.COM = {
        kdc = kdc.mycompany.com:88
        admin_server = kdc.mycompany.com:749
        default_domain = mycompany.com
    }

[domain_realm]
    .mycompany.com = MYCOMPANY.COM
    mycompany.com = MYCOMPANY.COM
```

**Replace:**
- `MYCOMPANY.COM` with your realm
- `kdc.mycompany.com` with your KDC server
- `mycompany.com` with your domain

### 1.3 Update Platform Configuration

```bash
cd platform-bootstrap
# Run the enhanced setup wizard with visual feedback
./dev-tools/setup-kerberos.sh
```

**The wizard features:**
- Clear section headers for each configuration step
- Automatic krb5.conf parsing and validation
- Built-in diagnostics for troubleshooting
- Support for testing both SQL Server and PostgreSQL connections

**When prompted, you'll configure:**
- Kerberos domain (e.g., `MYCOMPANY.COM`)
- Docker image selection (standard or corporate)
- Prebuilt mode for corporate images
- Optional database connection testing

**The wizard automatically creates:**
- `platform-config.yaml` with your settings
- `.env` file with all necessary environment variables

### 1.4 Validation
```bash
# Verify krb5.conf syntax
klist -V
# Should show: Kerberos 5 version X.Y.Z

# Check KDC is reachable
nc -zv kdc.mycompany.com 88
# Should connect successfully
```

**✅ Step 1 Complete:** Corporate Kerberos configured

---

## Step 2: Verify Credentials Cached in WSL2

### 2.1 Obtain Kerberos Ticket

```bash
# Get ticket for your corporate account
kinit YOUR_USERNAME@MYCOMPANY.COM
# Enter your corporate password when prompted
```

### 2.2 Verify Ticket Exists

```bash
# Check ticket details
klist

# Expected output:
# Ticket cache: FILE:/tmp/krb5cc_1000 (or DIR::/home/user/.krb5-cache/...)
# Default principal: YOUR_USERNAME@MYCOMPANY.COM
#
# Valid starting     Expires            Service principal
# 10/12/25 10:00:00  10/12/25 20:00:00  krbtgt/MYCOMPANY.COM@MYCOMPANY.COM
```

### 2.3 Verify Ticket File Location

```bash
# Run diagnostic to find exact location
cd platform-bootstrap
./diagnose-kerberos.sh
```

**The diagnostic will show:**
```
✓ Kerberos tickets found!
📍 Ticket cache location: FILE:/tmp/krb5cc_1000

Add to platform-bootstrap/.env:
KERBEROS_CACHE_TYPE=FILE
KERBEROS_CACHE_PATH=/tmp
KERBEROS_CACHE_TICKET=krb5cc_1000
```

### 2.4 Update .env with Detected Values

```bash
# The .env file was created by './platform setup' in Step 1.3
# Now add the Kerberos-specific values to it
nano .env

# Or use the automatic command provided by diagnostic
```

### 2.5 Validation
```bash
# Verify ticket is valid for at least 1 hour
klist | grep "Expires"
# Should show future expiration time

# Test ticket renewal (optional)
kinit -R
klist
# Expiration time should extend
```

**✅ Step 2 Complete:** Credentials cached and detectable

---

## Step 3: Test Direct SQL Server Connection from WSL2

**Goal:** Prove Kerberos authentication works to SQL Server WITHOUT Docker complexity.

### 3.1 Install SQL Server Client Tools

```bash
# Install FreeTDS (open-source SQL Server client)
sudo apt-get update
sudo apt-get install -y freetds-bin freetds-dev

# Verify installation
tsql -C
```

### 3.2 Configure FreeTDS

Create `~/.freetds.conf`:
```ini
[global]
    tds version = 7.4
    client charset = UTF-8

[test_server]
    host = sql-dev.mycompany.com
    port = 1433
    tds version = 7.4
```

### 3.3 Test Connection with Kerberos

```bash
# Connect using Kerberos (no password!)
tsql -S sql-dev.mycompany.com -U '' -P '' -K

# You should see:
# locale is "en_US.UTF-8"
# locale charset is "UTF-8"
# using default charset "UTF-8"
# 1>

# If connected, run test query:
1> SELECT @@VERSION
2> GO

# You should see SQL Server version info
```

### 3.4 Alternative: Use sqlcmd (if available)

```bash
# If you have Microsoft's sqlcmd installed
sqlcmd -S sql-dev.mycompany.com -E -Q "SELECT @@VERSION"
# -E means Windows Authentication (Kerberos)
```

### 3.5 Troubleshooting

**Connection fails:**
```bash
# Check ticket is still valid
klist

# Renew if expired
kinit -R

# Test network connectivity
nc -zv sql-dev.mycompany.com 1433

# Enable Kerberos tracing
export KRB5_TRACE=/dev/stdout
tsql -S sql-dev.mycompany.com -U '' -P '' -K
# Shows detailed Kerberos negotiation
```

**"Server principal not found":**
- SQL Server SPN may not be registered correctly
- Contact DBA to verify SPN: `MSSQLSvc/sql-dev.mycompany.com:1433`

**✅ Step 3 Complete:** Direct WSL2 → SQL Server authentication works

---

## Step 4: Test Container → SQL Server via Sidecar

**Goal:** Prove Docker containers can use sidecar's Kerberos tickets to authenticate.

### 4.1 Start Kerberos Sidecar

```bash
cd platform-bootstrap

# Start the full sidecar (not simple ticket copier)
docker compose -f developer-kerberos-standalone.yml up -d kerberos-platform-service

# Check it's running
docker ps | grep kerberos
```

### 4.2 Configure Sidecar Authentication

**For local testing with password:**
```bash
# Create password file (NOT for production!)
mkdir -p .secrets
echo "YOUR_PASSWORD" > .secrets/krb_password.txt
chmod 600 .secrets/krb_password.txt
```

**Edit developer-kerberos-standalone.yml if needed:**
```yaml
environment:
  KRB_PRINCIPAL: ${USER}@${COMPANY_DOMAIN}
  USE_PASSWORD: "true"  # For local dev
```

### 4.3 Verify Sidecar Obtained Ticket

```bash
# Check sidecar logs
docker logs kerberos-platform-service

# Should see:
# [timestamp] Starting Kerberos Ticket Manager
# [timestamp] Obtaining Kerberos ticket for principal: user@MYCOMPANY.COM
# [timestamp] Ticket obtained successfully

# Verify ticket in container
docker exec kerberos-platform-service klist
```

### 4.4 Test from Another Container

```bash
# Run test container that uses shared ticket
docker run --rm -it \
  --network platform_network \
  -v platform_kerberos_cache:/krb5/cache:ro \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  alpine:latest sh -c "
    apk add --no-cache krb5 freetds &&
    echo 'Checking ticket:' &&
    klist &&
    echo 'Testing SQL Server connection:' &&
    tsql -S sql-dev.mycompany.com -U '' -P '' -K <<< 'SELECT @@VERSION
GO
EXIT'
  "
```

**Expected output:**
- Ticket details from sidecar
- SQL Server version information
- Successful query execution

### 4.5 Troubleshooting

**Ticket not found in container:**
```bash
# Check volume exists
docker volume inspect platform_kerberos_cache

# Check sidecar is copying tickets
docker exec kerberos-platform-service ls -la /krb5/cache/

# Check volume mount in test container
docker run --rm \
  -v platform_kerberos_cache:/krb5/cache:ro \
  alpine ls -la /krb5/cache/
```

**Connection fails from container:**
```bash
# Test DNS resolution
docker run --rm --network platform_network alpine nslookup sql-dev.mycompany.com

# Test network connectivity
docker run --rm --network platform_network alpine nc -zv sql-dev.mycompany.com 1433

# Check krb5.conf is accessible
docker run --rm -v /etc/krb5.conf:/etc/krb5.conf:ro alpine cat /etc/krb5.conf
```

**✅ Step 4 Complete:** Container can authenticate via sidecar tickets

---

## Step 5: Test End-to-End Airflow DAG

**Goal:** Validate production pattern with Airflow DAG using KubernetesPodOperator or DockerOperator.

### 5.1 Create Test DAG

**File:** `~/test-dags/test_kerberos_connection.py`

```python
from airflow import DAG
from airflow.decorators import task
from airflow.providers.docker.operators.docker import DockerOperator
from datetime import datetime

with DAG(
    'test_kerberos_sql_server',
    start_date=datetime(2025, 1, 1),
    schedule_interval=None,
    catchup=False,
    tags=['test', 'kerberos']
) as dag:

    @task
    def test_ticket_available():
        """Verify Kerberos ticket is accessible."""
        import subprocess
        result = subprocess.run(['klist'], capture_output=True, text=True)
        print(result.stdout)
        assert result.returncode == 0, "No Kerberos ticket found"
        return "Ticket OK"

    @task
    def test_sql_server_connection():
        """Test SQL Server connection with Kerberos."""
        from sqlalchemy import create_engine, text

        # Connection string using Windows Authentication
        conn_str = (
            "mssql+pyodbc://sql-dev.mycompany.com/YourTestDB"
            "?driver=ODBC+Driver+17+for+SQL+Server"
            "&TrustServerCertificate=yes"
            "&Trusted_Connection=yes"  # Uses Kerberos
        )

        engine = create_engine(conn_str)

        with engine.connect() as conn:
            result = conn.execute(text("SELECT @@VERSION AS version"))
            version = result.fetchone()[0]
            print(f"Connected! SQL Server version: {version}")

        return "Connection successful"

    # Run tests in sequence
    test_ticket_available() >> test_sql_server_connection()
```

### 5.2 Set Up Airflow Project

```bash
# Create test Astronomer project
mkdir ~/test-airflow-kerberos
cd ~/test-airflow-kerberos
astro dev init

# Copy test DAG
cp ~/test-dags/test_kerberos_connection.py dags/
```

### 5.3 Configure docker-compose.override.yml

**File:** `docker-compose.override.yml`

```yaml
version: '3.8'

x-kerberos-config: &kerberos-config
  volumes:
    - platform_kerberos_cache:/krb5/cache:ro
  environment:
    - KRB5CCNAME=/krb5/cache/krb5cc

services:
  scheduler:
    <<: *kerberos-config

  webserver:
    <<: *kerberos-config

  triggerer:
    <<: *kerberos-config

volumes:
  platform_kerberos_cache:
    external: true
```

### 5.4 Add SQL Server Dependencies

**File:** `requirements.txt`

```txt
sqlalchemy>=2.0
pyodbc>=5.2.0
pymssql>=2.3.1
```

**File:** `packages.txt`

```txt
unixodbc
freetds
krb5-user
```

### 5.5 Start Airflow and Run Test

```bash
# Ensure sidecar is running
cd ~/airflow-data-platform/platform-bootstrap
docker compose -f developer-kerberos-standalone.yml up -d

# Start Airflow
cd ~/test-airflow-kerberos
astro dev start

# Wait for Airflow to be ready
# Access: http://localhost:8080

# Trigger the test DAG
astro dev run dags test test_kerberos_sql_server

# Or via UI: Enable and trigger the DAG
```

### 5.6 Verify Results

**In Airflow UI (http://localhost:8080):**
1. Navigate to DAGs
2. Find `test_kerberos_sql_server`
3. Check task logs:
   - `test_ticket_available` should show `klist` output
   - `test_sql_server_connection` should show SQL Server version

**Via CLI:**
```bash
# Check scheduler logs
docker logs test-airflow-kerberos-scheduler | grep -A 10 "test_kerberos"

# Check if tasks succeeded
astro dev run dags state test_kerberos_sql_server test_ticket_available
```

### 5.7 Troubleshooting

**"ModuleNotFoundError: No module named 'pyodbc'":**
```bash
# Rebuild Airflow image with new requirements
astro dev restart
```

**"Can't open lib 'ODBC Driver 17 for SQL Server'":**
```bash
# Check if driver is installed in Airflow container
docker exec test-airflow-kerberos-scheduler odbcinst -q -d
# Should show: ODBC Driver 17 for SQL Server
```

**"Login failed for user":**
```bash
# Check ticket in Airflow container
docker exec test-airflow-kerberos-scheduler klist

# Verify ticket is accessible
docker exec test-airflow-kerberos-scheduler ls -la /krb5/cache/

# Check environment variable
docker exec test-airflow-kerberos-scheduler env | grep KRB5
```

**✅ Step 5 Complete:** End-to-end Airflow DAG with Kerberos works!

---

## Success Criteria Checklist

By the end of this guide, you should have verified:

- [x] **Step 1:** Corporate Kerberos configured (krb5.conf, realm, KDC)
- [x] **Step 2:** `kinit` obtains ticket, `klist` shows valid ticket
- [x] **Step 3:** Direct connection from WSL2 to SQL Server works (tsql/sqlcmd)
- [x] **Step 4:** Docker container authenticates via sidecar tickets
- [x] **Step 5:** Airflow DAG successfully queries SQL Server

**If all steps pass:** Your Kerberos integration is production-ready for local development!

---

## What Each Step Proves

| Step | What Works | What You've Eliminated |
|------|-----------|------------------------|
| 1 | KDC reachable | Network/firewall issues |
| 2 | Kerberos auth | Credential problems |
| 3 | SQL Server SPN correct | Server configuration |
| 4 | Ticket sharing | Docker volume issues |
| 5 | Airflow integration | DAG/dependency problems |

---

## Common Failure Points

### Fails at Step 2 (kinit doesn't work)
**Likely causes:**
- Wrong password
- Account locked/expired
- KDC unreachable (VPN required?)
- krb5.conf misconfigured

**Resolution:**
- Verify password works on corporate Windows machine
- Check VPN connection
- Contact IT about account status
- Review krb5.conf with IT

### Fails at Step 3 (WSL2 → SQL Server)
**Likely causes:**
- SQL Server SPN not registered
- SQL Server doesn't accept Kerberos auth
- Network can't reach SQL Server
- Wrong server hostname/port

**Resolution:**
- Ask DBA to verify SPN exists
- Ensure SQL Server allows Windows Authentication
- Test with `telnet sql-server.com 1433`
- Verify hostname matches SPN

### Fails at Step 4 (Container → SQL Server)
**Likely causes:**
- Ticket not being copied to shared volume
- krb5.conf not accessible in container
- Network isolation (container can't reach KDC/SQL)

**Resolution:**
- Check `docker logs kerberos-platform-service`
- Verify volume mount: `docker exec container ls /krb5/cache`
- Test network: `docker run --network platform_network alpine nc -zv kdc.com 88`

### Fails at Step 5 (Airflow DAG)
**Likely causes:**
- Missing dependencies (pyodbc, ODBC drivers)
- docker-compose.override.yml not applied
- Volume not mounted to Airflow containers

**Resolution:**
- Check Dockerfile built requirements/packages
- Verify override file exists and is syntactically correct
- `docker inspect scheduler | grep -A 10 Mounts`

---

## Next Steps After Validation

Once all 5 steps pass:

### For Continued Local Development
- Keep using `developer-kerberos-standalone.yml`
- Sidecar handles ticket renewal automatically
- No manual `kinit` needed (sidecar does it)

### For Team Rollout
- Document your corporate-specific settings in platform-config.yaml
- Share krb5.conf with team
- Update platform-config.yaml template with your realm
- Commit to organizational fork

### For Kubernetes/Production
- See Issue #23 for Kubernetes deployment patterns
- Work with IT to obtain service account keytab
- Follow corporate image registry procedures

---

## Additional Resources

- **[Getting Started Guide](getting-started-simple.md)** - Initial platform setup
- **[Kerberos Diagnostic Guide](kerberos-diagnostic-guide.md)** - Understanding diagnose-kerberos.sh output
- **[Kerberos Setup for WSL2](kerberos-setup-wsl2.md)** - Detailed Kerberos configuration
- **[Issue #18](https://github.com/Troubladore/airflow-data-platform/issues/18)** - Kerberos sidecar implementation tracking
- **[Issue #23](https://github.com/Troubladore/airflow-data-platform/issues/23)** - Kubernetes deployment (future)

---

## Quick Reference Commands

```bash
# Step 1: Configure
sudo nano /etc/krb5.conf
cd platform-bootstrap && ./platform setup

# Step 2: Get ticket
kinit YOUR_USERNAME@MYCOMPANY.COM
klist

# Step 3: Test WSL2 direct
tsql -S sql-dev.mycompany.com -U '' -P '' -K

# Step 4: Test via sidecar
docker compose -f developer-kerberos-standalone.yml up -d
docker exec kerberos-platform-service klist

# Step 5: Test Airflow
cd ~/test-airflow-kerberos
astro dev start
# Trigger DAG in UI
```

---

*This progressive validation approach ensures each layer of your Kerberos integration works before moving to the next, making troubleshooting straightforward and building confidence in your setup.*
