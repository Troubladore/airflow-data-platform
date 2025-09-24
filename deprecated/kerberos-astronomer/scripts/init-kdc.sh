#!/bin/bash
# Initialize MIT Kerberos KDC for Testing
set -e

REALM="TEST.LOCAL"
DOMAIN="test.local"
ADMIN_PRINCIPAL="admin/admin"
ADMIN_PASSWORD="admin_password"

echo "Initializing Kerberos KDC for realm: $REALM"

# Create KDC database if it doesn't exist
if [ ! -f /var/kerberos/krb5kdc/principal ]; then
    echo "Creating KDC database..."
    kdb5_util create -s -P masterkey -r $REALM
fi

# Start KDC in background
krb5kdc &
kadmind &

sleep 5

# Create admin principal if it doesn't exist
kadmin.local -q "add_principal -pw $ADMIN_PASSWORD $ADMIN_PRINCIPAL@$REALM" 2>/dev/null || true

# Create service principals for testing
echo "Creating test principals..."

# Airflow service principal
kadmin.local -q "add_principal -pw airflow123 airflow@$REALM" 2>/dev/null || true

# SQL Server service principal (SPN)
kadmin.local -q "add_principal -pw sqlserver123 MSSQLSvc/sql.test.local:1433@$REALM" 2>/dev/null || true
kadmin.local -q "add_principal -pw sqlserver123 MSSQLSvc/sql.test.local@$REALM" 2>/dev/null || true

# HTTP service principals for web authentication
kadmin.local -q "add_principal -pw http123 HTTP/airflow.test.local@$REALM" 2>/dev/null || true

# Create keytabs for service accounts
echo "Generating keytabs..."

# Airflow keytab
kadmin.local -q "ktadd -k /var/kerberos/airflow.keytab airflow@$REALM" 2>/dev/null || true
chmod 644 /var/kerberos/airflow.keytab

# SQL Server keytab
kadmin.local -q "ktadd -k /var/kerberos/sqlserver.keytab MSSQLSvc/sql.test.local:1433@$REALM" 2>/dev/null || true
kadmin.local -q "ktadd -k /var/kerberos/sqlserver.keytab MSSQLSvc/sql.test.local@$REALM" 2>/dev/null || true
chmod 644 /var/kerberos/sqlserver.keytab

echo "KDC initialization complete"
echo "Test principals created:"
echo "  - airflow@$REALM (password: airflow123)"
echo "  - MSSQLSvc/sql.test.local:1433@$REALM"
echo "  - HTTP/airflow.test.local@$REALM"

# Keep the script running
wait
