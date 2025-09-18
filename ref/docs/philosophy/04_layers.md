# Bronze / Silver / Gold Layers

## Context
We needed a model for ingesting heterogeneous sources, normalizing them, and producing consistent analytic structures.

## Options
- **Single-layer landing**: fast, but messy, schema drift everywhere.
- **Custom multi-layer**: every team defines their own pattern.
- **Medallion (Bronze/Silver/Gold)**: industry-standard, clear responsibilities.

## Decision
Use **Bronze for raw ingests**, **Silver for typed/enriched tables**, **Gold for facts/dimensions**.

## Implications
- Bronze uses **datakits** (Python, SQLModel, PySpark).
- Silver/Gold use **dbt** (SQL-first, approachable).
- Dimensions conformed in a central package, facts join to them.
