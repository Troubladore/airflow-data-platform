# Routing, TLS, and Local Domains

## Context
We needed a way for developers to access multiple contract environments locally in a way that matched production routing patterns, while passing IT security review.

## Options
- **Hosts file edits**: not possible (no admin rights).
- **lvh.me / nip.io**: blocked by IT (DNS hijacking risk).
- **.localhost domains with Traefik**: RFC-6761 reserved, secure, no external DNS.

## Decision
Adopted **Traefik with .localhost subdomains**, terminating TLS locally with mkcert-generated certs.

## Implications
- Devs train with URLs like `airflow-dev.customer.localhost` that mirror prod `airflow-dev.customer.myco.com`.
- IT happy (no external DNS).
- TLS is terminated once at Traefik; services behind don’t manage certs directly.
