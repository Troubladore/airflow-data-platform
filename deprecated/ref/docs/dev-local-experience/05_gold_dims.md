# 5. Gold Dimensions (dbt-core-dimensions)

Purpose: single-source conformed dimensions used by all topics.

Steps:
1. Unzip `dbt-core-dimensions`.
2. Configure profile (as before).
3. Run build:
   ```bash
   dbt deps
   dbt build
   ```

Outputs:
- Tables in `gold_mart`: `dim_film`, `dim_store`, `dim_staff`, `dim_date`.
- These are re-used downstream, preventing drift across topics.
