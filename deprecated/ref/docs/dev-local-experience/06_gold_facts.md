# 6. Gold Facts (dbt-gold-rental)

Purpose: business facts joined with conformed dimensions.

Steps:
1. Unzip `dbt-gold-rental`.
2. Configure profile.
3. Run build:
   ```bash
   dbt deps
   dbt build
   ```

Outputs:
- Table in `gold_rental.fact_rental`.
- Contains planned vs. actual rental metrics, revenue, and dimensional joins.
