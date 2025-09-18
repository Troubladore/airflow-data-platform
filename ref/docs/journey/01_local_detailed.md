# 1) Local Journey — Detailed, From Traefik Onward

> Goal: Stand up local routing + local registry, run Bronze→Silver→Gold end-to-end, and prove the shapes match what we expect.

## A. Traefik + Local TLS + Local Registry

### What you will accomplish
- A reverse proxy on WSL2 that routes `https://airflow-<env>.<customer>.localhost` to your containers.
- TLS termination by Traefik using the IT-provided mkcert flow.
- A local OCI registry at `registry.localhost` for your runner images.

### Steps

1. **Clone the bundle repo** (or place the provided bundle folder):
   ```bash
   cd ~/work
   git clone <your/astro-local-config>    # or unpack the provided bundle
   cd astro-local-config/traefik-bundle
   ```

2. **Place certificates** produced by your IT flow:
   - You should have a `copy-to-wsl.sh` (or similar) that places `fullchain.pem` and `privkey.pem` under a path you control.
   - Copy them into the bundle:
     ```bash
     mkdir -p tls
     cp /etc/ssl/local-dev/fullchain.pem tls/localhost.crt
     cp /etc/ssl/local-dev/privkey.pem   tls/localhost.key
     ```

3. **Start Traefik + registry**:
   ```bash
   docker compose up -d
   ```

4. **Trust the CA** (if not handled already by IT):
   - Follow the approved company steps to trust the mkcert CA in Windows and your browsers.
   - This ensures `https://*.localhost` is trusted.

### Verify

- **Traefik health**:
  ```bash
  docker ps | grep traefik
  curl -vk https://localhost/  # should return 404 from Traefik (proof of TLS + listener)
  ```
- **Registry health**:
  ```bash
  docker ps | grep registry
  docker pull busybox
  docker tag busybox registry.localhost/test/busybox:latest
  docker push registry.localhost/test/busybox:latest
  docker manifest inspect registry.localhost/test/busybox:latest | head
  ```
  Expect manifest JSON. If push fails, check that Traefik routes `registry.localhost:443` to the registry service.

---

## B. Build and Push Runner Images

> We standardize execution with **runner images** you can call from Airflow or locally.

1. **dbt-runner**:
   ```bash
   cd ~/work/dbt-runner
   docker build -t registry.localhost/analytics/dbt-runner:1.0.0 .
   docker push registry.localhost/analytics/dbt-runner:1.0.0
   ```
   **Test**:
   ```bash
   docker run --rm registry.localhost/analytics/dbt-runner:1.0.0 dbt --version
   ```

2. **Bronze datakit** (Pagila example):
   ```bash
   cd ~/work/datakit-bronze-pagila-runner
   docker build -t registry.localhost/etl/datakit-bronze:0.1.0 .
   docker push registry.localhost/etl/datakit-bronze:0.1.0
   ```
   **Test**:
   ```bash
   docker run --rm registry.localhost/etl/datakit-bronze:0.1.0 --help
   ```

---

## C. Provision Local Postgres (Warehouse)

> You need a Postgres with DBs/schemas: `pagila` (source) and `pagila_wh` (warehouse).

- If you already have a Postgres, skip to verification.
- Otherwise, run a local container:
  ```bash
  docker run -d --name pg     -e POSTGRES_PASSWORD=postgres     -p 5432:5432     postgres:16
  ```

- **Load Pagila** (use your company’s seed or public dump). After load, verify:
  ```bash
  psql "postgresql://postgres:postgres@localhost:5432/pagila" -c "\dt public.*"
  ```

- **Create warehouse DB** and the bronze schema:
  ```bash
  psql "postgresql://postgres:postgres@localhost:5432/postgres" -c "create database pagila_wh;"
  psql "postgresql://postgres:postgres@localhost:5432/pagila_wh" -c "create schema if not exists bronze;"
  ```

**Verify**: Both DBs exist and are reachable.

---

## D. Land Bronze Data (Datakit)

> Land a few tables to prove the pipe works end-to-end.

Example (film, address, store, language, customer, staff, rental, payment, inventory):

```bash
for t in film address store language customer staff rental payment inventory; do
  docker run --rm registry.localhost/etl/datakit-bronze:0.1.0 ingest     --table $t     --source-url postgresql+psycopg://postgres:postgres@host.docker.internal:5432/pagila     --target-url postgresql+psycopg://postgres:postgres@host.docker.internal:5432/pagila_wh     --batch-id $(date +%Y%m%dT%H%M%S)
done
```

**Verify**:
```bash
psql "postgresql://postgres:postgres@localhost:5432/pagila_wh" -c "\dn"
psql "postgresql://postgres:postgres@localhost:5432/pagila_wh" -c "\dt bronze.*"
```

Expect `br_*` tables under `bronze`.

---

## E. Build Silver (dbt-silver-core)

1. Prepare dbt profile (one-time):
   ```bash
   mkdir -p ~/.dbt
   cat > ~/.dbt/profiles.yml <<'YAML'
pagila:
  target: dev
  outputs:
    dev:
      type: postgres
      host: localhost
      user: postgres
      password: postgres
      dbname: pagila_wh
      schema: pagila_silver
      port: 5432
      threads: 4
YAML
   ```

2. Run dbt:
   ```bash
   cd ~/work/dbt-silver-core
   dbt debug
   dbt build
   ```

**Verify**:
```bash
psql "postgresql://postgres:postgres@localhost:5432/pagila_wh" -c "\dt pagila_silver.*"
```

Expect `sl_film`, `sl_store`, `sl_customer`, `sl_staff`, `sl_inventory`, `sl_rental_enriched`, etc.

---

## F. Build Conformed Dims (dbt-core-dimensions)

```bash
cd ~/work/dbt-core-dimensions
dbt deps
dbt build
```

**Verify**:
```bash
psql "postgresql://postgres:postgres@localhost:5432/pagila_wh" -c "\dt gold_mart.*"
```

Expect `dim_film`, `dim_store`, `dim_staff`, `dim_date`.

---

## G. Build Topic Fact (dbt-gold-rental)

1. Ensure `packages.yml` in `dbt-gold-rental` points to your `dbt-core-dimensions` (or use local install if you’ve packaged it).
2. Run:
   ```bash
   cd ~/work/dbt-gold-rental
   dbt deps
   dbt build
   ```

**Verify**:
```bash
psql "postgresql://postgres:postgres@localhost:5432/pagila_wh" -c "\dt gold_rental.*"
psql "postgresql://postgres:postgres@localhost:5432/pagila_wh" -c "select count(*) from gold_rental.fact_rental;"
```

Expect a nonzero count and valid foreign keys into gold_mart dims.

---

## H. Sanity Tests (Quick)

- Spot-check joins:
  ```bash
  psql "postgresql://postgres:postgres@localhost:5432/pagila_wh" -c "
  select f.title, d.language_name
  from gold_mart.dim_film d
  join pagila_silver.sl_film f using (film_id)
  limit 5;"
  "

- Validate referential links (sample):
  ```bash
  psql "postgresql://postgres:postgres@localhost:5432/pagila_wh" -c "
  select count(*) bad
  from gold_rental.fact_rental fr
  left join gold_mart.dim_film df on df.gl_dim_film_key = fr.film_key
  where df.gl_dim_film_key is null;"
  "

Should be zero.

---

## I. Troubleshooting

- **Registry push fails**: ensure Traefik is routing `registry.localhost:443` to the registry, and the cert is trusted.
- **dbt can’t connect**: verify Postgres is reachable from WSL2 (`psql`), credentials match `profiles.yml`, and port 5432 open.
- **Empty Silver/Gold**: ensure Bronze landed tables in `pagila_wh.bronze.*`. Re-run Bronze ingestion for missing tables.
