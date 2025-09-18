# Secrets Management and Kerberos

## Context
Sources require Kerberos/LDAP auth; secrets must align with corporate security.

## Options
- **Local caches**: fragile, inconsistent.
- **Delinea**: not integrated with our cloud strategy.
- **Azure Key Vault**: enterprise standard, cloud-native.
- **Kerberos sidecar**: ticket cache shared via container.

## Decision
- **Azure Key Vault** (or ESO) for secrets.
- **Kerberos sidecar container** (Option B) reusable across repos.

## Implications
- Same sidecar image can be used by multiple projects.
- Dev and prod parity: the same Kerberos story everywhere.
