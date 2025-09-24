# Kerberos Sidecar for Astronomer Airflow

A production-ready Kerberos sidecar container that enables SQL Server NT Authentication for Astronomer-based Airflow deployments. This platform component provides automatic ticket management and renewal for containerized environments.

## 🎯 Problem Statement

Enterprise data sources requiring NT Authentication/Kerberos are inaccessible to containerized Airflow deployments without proper ticket management. This sidecar bridges that gap by:

- Managing Kerberos ticket lifecycle (acquisition and renewal)
- Sharing tickets via Docker volumes with Airflow containers
- Supporting both keytab (production) and password (development) authentication
- Providing health checks and monitoring

## 🏗️ Architecture

```
┌─────────────────────┐     ┌──────────────────┐
│                     │     │                  │
│  Kerberos Sidecar   │────▶│  Shared Volume   │
│  (Ticket Manager)   │     │  (/krb5/cache)   │
│                     │     │                  │
└─────────────────────┘     └────────┬─────────┘
                                     │
                           ┌─────────▼─────────┐
                           │                   │
                           │  Airflow Services │
                           │  - Webserver      │
                           │  - Scheduler      │
                           │  - Workers        │
                           │                   │
                           └───────────────────┘
                                     │
                                     ▼
                           ┌───────────────────┐
                           │                   │
                           │   SQL Server      │
                           │   (NT Auth)       │
                           │                   │
                           └───────────────────┘
```

## 🚀 Quick Start

### Prerequisites

1. **WSL2 Environment** with Kerberos configured:
   ```bash
   # Verify krb5.conf exists
   ls -la /etc/krb5.conf

   # Test Kerberos connectivity
   kinit your_username@COMPANY.COM
   klist
   ```

2. **Docker and Docker Compose** installed

3. **Astronomer CLI** (optional but recommended):
   ```bash
   curl -sSL install.astronomer.io | sudo bash -s
   ```

### Setup Steps

1. **Clone and navigate to directory:**
   ```bash
   cd kerberos-astronomer
   ```

2. **Configure environment:**
   ```bash
   cp .env.template .env
   # Edit .env with your settings
   ```

3. **Validate configuration:**
   ```bash
   chmod +x scripts/validate-kerberos.sh
   ./scripts/validate-kerberos.sh
   ```

4. **Build images:**
   ```bash
   # Build Kerberos sidecar
   docker build -f Dockerfile.kerberos-sidecar -t kerberos-sidecar:latest .

   # Build Astronomer with Kerberos support
   docker build -f Dockerfile.astronomer-kerberos -t astronomer-kerberos:latest .
   ```

5. **Start services:**
   ```bash
   # For production environment
   docker-compose -f docker-compose.override.yml up -d

   # For local testing with KDC
   docker-compose -f docker-compose.kdc-test.yml up -d
   ```

## 📋 Configuration

### Environment Variables

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `KRB_PRINCIPAL` | Service principal name | `svc_airflow@COMPANY.COM` | Yes |
| `KRB_REALM` | Kerberos realm | `COMPANY.COM` | Yes |
| `KRB_KEYTAB_PATH` | Path to keytab in container | `/krb5/keytabs/airflow.keytab` | Prod only |
| `KRB_RENEWAL_INTERVAL` | Ticket renewal interval (seconds) | `3600` | No |
| `USE_PASSWORD` | Enable password auth (dev only) | `true` | Dev only |
| `KRB_PASSWORD` | Password for principal | `secretpass` | Dev only |
| `KRB5_CONF_HOST` | Host path to krb5.conf | `/etc/krb5.conf` | Yes |

### Production Configuration

For production, use keytab-based authentication:

1. **Generate keytab** (on a domain-joined machine):
   ```bash
   ktutil
   addent -password -p svc_airflow@COMPANY.COM -k 1 -e aes256-cts
   wkt airflow.keytab
   quit
   ```

2. **Place keytab** in `./config/airflow.keytab`

3. **Set permissions:**
   ```bash
   chmod 600 ./config/airflow.keytab
   ```

### Development Configuration

For development without domain access:

1. **Enable password mode** in `.env`:
   ```bash
   USE_PASSWORD=true
   KRB_PASSWORD=your_dev_password
   ```

2. **Use test KDC:**
   ```bash
   docker-compose -f docker-compose.kdc-test.yml up -d
   ```

## 🔍 Validation and Troubleshooting

### Check Kerberos Ticket Status

```bash
# In sidecar container
docker exec kerberos-sidecar klist

# In Airflow container
docker exec airflow-scheduler klist
```

### View Sidecar Logs

```bash
docker-compose logs -f kerberos-sidecar
```

### Common Issues

1. **"No valid ticket found"**
   - Check KRB5CCNAME environment variable
   - Verify ticket cache volume is mounted correctly
   - Ensure sidecar is running and healthy

2. **"Cannot contact KDC"**
   - Verify network connectivity to KDC
   - Check krb5.conf configuration
   - Ensure DNS resolution works

3. **"Permission denied on keytab"**
   - Check keytab file permissions
   - Verify keytab is mounted correctly
   - Ensure principal matches keytab

## 🔐 Security Considerations

1. **Keytab Protection:**
   - Never commit keytabs to version control
   - Use secrets management in production (Azure Key Vault, K8s secrets)
   - Rotate keytabs regularly

2. **Network Security:**
   - Kerberos requires specific ports (88/tcp, 88/udp)
   - Use TLS for SQL Server connections
   - Implement network policies in K8s

3. **Container Security:**
   - Run containers as non-root user
   - Use read-only volumes where possible
   - Implement resource limits

## 📦 Integration with Astronomer

### Using in Astronomer Project

1. **Update Dockerfile:**
   ```dockerfile
   FROM astronomer-kerberos:latest
   # Your additional customizations
   ```

2. **Add to docker-compose.override.yml:**
   ```yaml
   services:
     scheduler:
       depends_on:
         - kerberos-sidecar
   ```

3. **Configure Airflow connection:**
   - Connection ID: `mssql_kerberos`
   - Type: `mssql`
   - Host: `sql.company.com`
   - Schema: `DataWarehouse`
   - Extra: `{"auth_type": "kerberos"}`

## 🧪 Testing

### Local Testing with Mock KDC

```bash
# Start test environment
docker-compose -f docker-compose.kdc-test.yml up -d

# Create test principal
docker exec kdc kadmin.local -q "addprinc -pw test123 test@TEST.LOCAL"

# Test authentication
docker exec krb-client kinit test@TEST.LOCAL
```

### Integration Testing

See the `airflow-data-platform-examples` repository for complete DAG examples and integration patterns.

## 📚 References

- [Astronomer Documentation](https://docs.astronomer.io)
- [MIT Kerberos Documentation](https://web.mit.edu/kerberos/krb5-latest/doc/)
- [SQL Server Kerberos Configuration](https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/register-a-service-principal-name-for-kerberos-connections)

## 🤝 Contributing

This is a platform component of the airflow-data-platform. For usage examples and patterns, contribute to the `airflow-data-platform-examples` repository.

## 📝 License

Part of the airflow-data-platform project.
