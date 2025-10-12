# Layer 1 – Platform Foundation

**🏗️ Platform foundation components for the Astronomer Airflow data engineering environment**

## 📋 Prerequisites

Before using these platform components, ensure your development environment is set up:

**🎯 Quick Setup**: See [README-PLATFORM-SETUP.md](../README-PLATFORM-SETUP.md) for complete environment setup instructions.

## 🐳 Platform Base Image

This platform defines the **true Airflow runtime** your projects inherit:

- **Upstream base**: `astrocrpublic.azurecr.io/runtime:3.0-10` (includes Apache Airflow 3.0.6+astro.1)
- **Platform base image tag**: `registry.localhost/platform/airflow-base:3.0-10`
- **Queues**: default, mssql-kerb, pg, dbt, io-heavy, compute-heavy, validation, adhoc
- **Pod templates**: one per queue (where applicable), with names matching queues
- **Settings**: `airflow_settings/airflow_settings.yaml` imported into both local and prod

## 🚀 Build & Deploy

**After completing platform setup** from the main guide:

```bash
# Build platform base image
docker build -f docker/airflow-base.Dockerfile \
  -t registry.localhost/platform/airflow-base:3.0-10 .

# Push to local registry
docker push registry.localhost/platform/airflow-base:3.0-10

# Verify in registry
curl -k https://registry.localhost/v2/_catalog
```
