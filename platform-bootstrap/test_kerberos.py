#!/usr/bin/env python3
"""
Test Kerberos authentication with SQL Server.
This script validates that your Kerberos setup is working correctly.
"""

import os
import sys

# Check if we're in a container with Kerberos ticket
krb5ccname = os.environ.get("KRB5CCNAME")
if krb5ccname:
    print(f"✓ Found Kerberos ticket cache at: {krb5ccname}")
else:
    print("⚠️  No KRB5CCNAME environment variable set")
    print("   This test should be run in a Docker container with Kerberos tickets mounted")

# Try to import pyodbc (will fail if not installed)
try:
    import pyodbc

    print("✓ pyodbc module available")
except ImportError:
    print("✗ pyodbc not installed - SQL Server connections won't work")
    print("  Install with: pip install pyodbc")
    sys.exit(1)

# Get connection details from environment or use defaults
SERVER = os.environ.get("SQL_SERVER", "sqlserver.company.com")
DATABASE = os.environ.get("SQL_DATABASE", "TestDB")

print(f"\n🔌 Testing connection to {SERVER}/{DATABASE}...")

# Build connection string for Kerberos
conn_str = (
    f"DRIVER={{ODBC Driver 17 for SQL Server}};"
    f"SERVER={SERVER};"
    f"DATABASE={DATABASE};"
    f"Trusted_Connection=yes;"
    f"Authentication=Kerberos;"
)

try:
    # This will use your Kerberos ticket
    conn = pyodbc.connect(conn_str)
    cursor = conn.cursor()

    # Simple test query
    cursor.execute("SELECT @@VERSION")
    row = cursor.fetchone()

    print("\n✅ SUCCESS! Connected via Kerberos!")
    print(f"SQL Server Version: {row[0][:80]}...")

    # Test we can query a simple table
    cursor.execute("SELECT SYSTEM_USER")
    user = cursor.fetchone()
    print(f"Connected as: {user[0]}")

    cursor.close()
    conn.close()

except pyodbc.Error as e:
    print(f"\n❌ Connection failed: {e}")
    print("\n🔍 Troubleshooting checklist:")
    print("1. Do you have a valid Kerberos ticket?")
    print("   Check with: klist")
    print("2. Is the SQL Server reachable?")
    print(f"   Try: ping {SERVER}")
    print("3. Is your krb5.conf properly configured?")
    print("   Check: cat /etc/krb5.conf")
    print("4. Are you running this in a container with tickets mounted?")
    print(f"   KRB5CCNAME should be set: {krb5ccname}")
    sys.exit(1)

except Exception as e:
    print(f"\n❌ Unexpected error: {e}")
    sys.exit(1)

print("\n🎉 Kerberos authentication is working perfectly!")
print("You're ready to use SQL Server with Astronomer!")
