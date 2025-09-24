# 3. Bronze Layer (Datakits)

Purpose: land source data into the warehouse in a 1:1 raw-but-audited form.

Steps:
1. Build the bronze datakit image:
   ```bash
   cd datakit-bronze-pagila-runner
   docker build -t registry.localhost/etl/datakit-bronze:0.1.0 .
   ```

2. Run ingestion:
   ```bash
   docker run --rm registry.localhost/etl/datakit-bronze:0.1.0 ingest      --table film      --source-url postgresql+psycopg://.../pagila      --target-url postgresql+psycopg://.../pagila_wh      --batch-id $(date +%Y%m%dT%H%M%S)
   ```

3. Verify in Postgres: tables appear under `bronze.*`.
