# platform-krb-renewer

A tiny container that obtains and renews Kerberos tickets and writes a **ccache** to `/ccache/krb5cc`.
Use it both locally (Docker) and in prod (K8s sidecar).

## Env
- `KRB5_PRINCIPAL` (e.g., `svc_airflow@REALM`)
- `KRB5_KEYTAB` (path inside container, default `/secrets/airflow.keytab`)
- `KRB5_CCNAME` (default `/ccache/krb5cc`)
- `RENEW_SECONDS` (default 3600)

## Local (Docker compose snippet)
```yaml
services:
  krb-renewer:
    image: registry.localhost/platform/krb-renewer:0.1.0
    environment:
      KRB5_PRINCIPAL: "svc_airflow@EXAMPLE.COM"
      KRB5_KEYTAB: "/secrets/airflow.keytab"
      KRB5_CCNAME: "/ccache/krb5cc"
      RENEW_SECONDS: 3600
    volumes:
      - ./krb-ccache:/ccache
      - ./secrets:/secrets:ro
    restart: unless-stopped
```
