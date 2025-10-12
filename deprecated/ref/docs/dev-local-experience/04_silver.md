# 4. Silver Layer (dbt-silver-core)

Purpose: conform and type data for analytics, adding audit + enrichment.

Steps:
1. Unzip `dbt-silver-core`.
2. Configure `~/.dbt/profiles.yml` from `profiles-example/`.
3. Run build:
   ```bash
   dbt debug
   dbt build
   ```

Outputs:
- Tables in `pagila_silver` schema: `sl_film`, `sl_store`, `sl_customer`, `sl_staff`, `sl_inventory`, `sl_rental_enriched`, etc.

4. Explore with psql or VS Code database plugin.
