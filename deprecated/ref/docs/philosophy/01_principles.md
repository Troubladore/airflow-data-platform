# Core Principles

## Context
Our work must satisfy government contracts, strict data isolation, and developer productivity goals. We need a platform that is robust, secure, and approachable by multiple roles (Python developers, SQL analysts, data engineers).

## Principles
1. **Fidelity**: Local environments should mimic production as closely as possible.
2. **Separation of Concerns**: Data flows layered into Bronze, Silver, Gold medallion model.
3. **Single Source of Truth**: Dimensions defined once, reused across topics.
4. **Modularity**: Datakits (Python) and dbt (SQL) decouple reusable logic from orchestration.
5. **Sustainability**: Runners, registries, TLS, and secrets are reusable and maintainable.
