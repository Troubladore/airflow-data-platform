# Fidelity (Local ⇄ Prod)

Keep these identical:

1. **Base lineage**
   - Contract images use `FROM registry.localhost/platform/airflow-base:3.0-10` locally and the corresponding registry in prod.
   - Platform base is built `FROM astrocrpublic.azurecr.io/runtime:3.0-10`.

2. **Providers pinned** via requirements in this repo.

3. **Queues, pools, roles** imported from `airflow_settings/airflow_settings.yaml`.

4. **Pod template names** match queues; tasks set `queue=...` or use KPO with matching template.

5. **Secrets** over AKV; same env var names.

6. **DAG packaging** baked into images (no bind mounts required in prod).
