# Kerberos Sidecar Architecture: Two Modes, One Implementation

## Overview

The Kerberos sidecar supports **two modes** with a single unified implementation:
- **COPY mode** - Local development (copies your kinit tickets)
- **CREATE mode** - Production/K8s (creates tickets via keytab/password)

## Mode Selection

Set via environment variable: `TICKET_MODE=copy` or `TICKET_MODE=create`

### Local Development (COPY mode)

**Use when:**
- Developer workstation (WSL2, Mac, Linux)
- You run `kinit` to get tickets
- No passwords should touch the ground
- Testing locally before K8s deployment

**How it works:**
```yaml
environment:
  TICKET_MODE: copy
volumes:
  - ${KERBEROS_TICKET_DIR}:/host/tickets:ro  # Your kinit tickets
  - platform_kerberos_cache:/krb5/cache:rw   # Shared with other services
```

Sidecar:
1. Searches `/host/tickets` recursively for ticket files
2. Copies most recent valid ticket to `/krb5/cache/krb5cc`
3. Refreshes every 5 minutes (COPY_INTERVAL)
4. NO password or keytab needed

### Production/K8s (CREATE mode)

**Use when:**
- Kubernetes pods
- CI/CD pipelines
- Service accounts with keytabs
- No human kinit available

**How it works:**
```yaml
environment:
  TICKET_MODE: create
  KRB_PRINCIPAL: svc_airflow@COMPANY.COM
  KRB_KEYTAB_PATH: /krb5/keytabs/airflow.keytab
volumes:
  - keytab-secret:/krb5/keytabs:ro
  - kerberos-cache:/krb5/cache:rw
```

Sidecar:
1. Creates tickets via `kinit -kt` (keytab) or `kinit` (password)
2. Renews before expiration
3. Logs errors if can't obtain
4. Requires keytab file or password

## Multiple Service Support

**One sidecar serves ALL services:**

```yaml
services:
  # ONE sidecar (either mode)
  kerberos-sidecar:
    environment:
      TICKET_MODE: copy  # or create
    volumes:
      - platform_kerberos_cache:/krb5/cache:rw

  # MULTIPLE consumers
  airflow-scheduler:
    volumes:
      - platform_kerberos_cache:/krb5/cache:ro
    environment:
      - KRB5CCNAME=/krb5/cache/krb5cc

  airflow-webserver:
    volumes:
      - platform_kerberos_cache:/krb5/cache:ro
    environment:
      - KRB5CCNAME=/krb5/cache/krb5cc

  openmetadata:
    volumes:
      - platform_kerberos_cache:/krb5/cache:ro
    environment:
      - KRB5CCNAME=/krb5/cache/krb5cc

  # Any other service needing Kerberos...
```

**Benefits:**
- ✅ One sidecar for everything
- ✅ Airflow, OpenMetadata, custom services all share tickets
- ✅ Sidecar doesn't care about consumers
- ✅ Add new services by just mounting volume

## Configuration Examples

### Local Development (.env)
```bash
COMPANY_DOMAIN=MYCOMPANY.COM
KERBEROS_TICKET_DIR=${HOME}/.krb5-cache
TICKET_MODE=copy
```

### Production (K8s ConfigMap)
```yaml
COMPANY_DOMAIN: MYCOMPANY.COM
TICKET_MODE: create
KRB_PRINCIPAL: svc_airflow@MYCOMPANY.COM
KRB_KEYTAB_PATH: /krb5/keytabs/airflow.keytab
```

## Workflow

### Local Development
```bash
# 1. Get your ticket (normal workflow)
kinit you@COMPANY.COM

# 2. Start platform
make platform-start

# Sidecar automatically:
# - Finds your ticket in KERBEROS_TICKET_DIR
# - Copies to shared volume
# - Refreshes every 5 minutes
# - All containers get Kerberos access
```

### Production/K8s
```bash
# 1. Create keytab secret (one time)
kubectl create secret generic airflow-keytab --from-file=airflow.keytab

# 2. Deploy with TICKET_MODE=create
# Sidecar automatically:
# - Creates tickets from keytab
# - Renews before expiration
# - All pods get Kerberos access
```

## Why This Design

**Same sidecar everywhere:**
- ✅ Test locally with copy mode
- ✅ Deploy to K8s with create mode
- ✅ One implementation, two behaviors

**Security:**
- ✅ Local: No passwords in config (uses your kinit)
- ✅ Production: Keytab in K8s secrets (secure)
- ✅ Passwords never in .env files

**Flexibility:**
- ✅ Works with any service needing Kerberos
- ✅ Airflow, OpenMetadata, custom tools
- ✅ Just mount the volume

## Troubleshooting

**Local dev - "No tickets found":**
- Check: `klist` (do you have tickets?)
- Check: KERBEROS_TICKET_DIR matches `klist` output
- Check: `docker logs kerberos-platform-service`

**Production - "Ticket acquisition failed":**
- Check: Keytab file exists and is mounted
- Check: KRB_PRINCIPAL matches keytab
- Check: `docker logs sidecar`
