# Conformed Dimensions

## Context
Facts often repeat dimensions (e.g., customer, date, store). If each topic owned its own dims, drift was guaranteed.

## Options
- **Per-topic dims**: quick to build, but drift-prone, inconsistent.
- **Central package**: one repo builds all conformed dims.

## Decision
Centralize dims in **dbt-core-dimensions**, materialized to `gold_mart` schema.

## Implications
- Facts across topics reference the same keys.
- Clear ownership: the dimensions package team is responsible for drift prevention and governance.
- Easy to add SCD2 via dbt snapshots later.
