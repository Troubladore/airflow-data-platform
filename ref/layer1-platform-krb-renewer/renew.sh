#!/usr/bin/env bash
set -euo pipefail

: "${KRB5_KEYTAB:?KRB5_KEYTAB must be set}"
: "${KRB5_PRINCIPAL:?KRB5_PRINCIPAL must be set}"
: "${KRB5_CCNAME:=/ccache/krb5cc}"
: "${RENEW_SECONDS:=3600}"

mkdir -p "$(dirname "$KRB5_CCNAME")"
touch "$KRB5_CCNAME" || true

echo "[krb-renewer] kinit for $KRB5_PRINCIPAL using $KRB5_KEYTAB -> $KRB5_CCNAME"
kinit -k -t "$KRB5_KEYTAB" "$KRB5_PRINCIPAL"

while true; do
  sleep "$RENEW_SECONDS"
  echo "[krb-renewer] renewing ticket: $(date -Iseconds)"
  kinit -R || kinit -k -t "$KRB5_KEYTAB" "$KRB5_PRINCIPAL"
done
