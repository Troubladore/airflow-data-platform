# Layer 1 – Platform (Airflow 3.0.6 via Astronomer Runtime 3.0-10)

This platform repo defines the **true Airflow runtime** your contracts inherit.

- **Upstream base**: `astrocrpublic.azurecr.io/runtime:3.0-10` (includes Apache Airflow 3.0.6+astro.1)
- **Platform base image tag**: `registry.localhost/platform/airflow-base:3.0-10`
- **Queues**: default, mssql-kerb, pg, dbt, io-heavy, compute-heavy, validation, adhoc
- **Pod templates**: one per queue (where applicable), with names matching queues.
- **Settings**: `airflow_settings/airflow_settings.yaml` imported into both local and prod.

## Build & push locally
```bash
docker build -f docker/airflow-base.Dockerfile \
  -t registry.localhost/platform/airflow-base:3.0-10 .

docker push registry.localhost/platform/airflow-base:3.0-10
```
