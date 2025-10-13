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
    error_str = str(e).lower()
    print(f"\n❌ Connection failed: {e}")

    # Smart error detection - provide ONE specific fix based on error type
    print("\n" + "=" * 70)

    # SPN (Service Principal Name) issues
    if "cannot generate sspi context" in error_str or "login failed" in error_str:
        print("🔍 DIAGNOSIS: SQL Server SPN (Service Principal Name) Issue")
        print("=" * 70)
        print()
        print("This error means SQL Server's Kerberos identity is not registered")
        print("correctly in Active Directory. This MUST be fixed by your DBA.")
        print()
        print("WHAT TO TELL YOUR DBA:")
        print("-" * 70)
        print(f"Hi, I need help with Kerberos authentication to {SERVER}.")
        print()
        print("Error: 'Cannot generate SSPI context' or 'Login failed'")
        print()
        print("This typically means the SQL Server's SPN is not registered.")
        print("Can you verify and register the following SPNs in Active Directory?")
        print()
        print(f"  MSSQLSvc/{SERVER}:1433")
        print(f"  MSSQLSvc/{SERVER}")
        print()
        print("Registration commands (run as Domain Admin):")
        print(f"  setspn -A MSSQLSvc/{SERVER}:1433 <SQL_SERVICE_ACCOUNT>")
        print(f"  setspn -A MSSQLSvc/{SERVER} <SQL_SERVICE_ACCOUNT>")
        print()
        print("Where <SQL_SERVICE_ACCOUNT> is the AD account running SQL Server.")
        print()
        print("To check current SPNs:")
        print("  setspn -L <SQL_SERVICE_ACCOUNT>")
        print("-" * 70)
        print()
        print("WHAT YOU CAN DO:")
        print("  1. Copy the message above and send to your DBA")
        print("  2. Or use the helper script: ./check-sql-spn.sh")
        print("  3. Wait for DBA to register SPNs")
        print("  4. Re-run this test")

    # Network/connectivity issues
    elif (
        "timeout" in error_str
        or "cannot open" in error_str
        or "server not found" in error_str
        or "unable to connect" in error_str
    ):
        print("🔍 DIAGNOSIS: Network Connectivity Issue")
        print("=" * 70)
        print()
        print("Cannot reach the SQL Server. This is a network problem.")
        print()
        print("IMMEDIATE ACTIONS:")
        print(f"  1. Test basic connectivity: nc -zv {SERVER} 1433")
        print(f"  2. Try ping: ping {SERVER}")
        print()
        print("COMMON CAUSES:")
        print("  - Not connected to corporate VPN")
        print("  - Firewall blocking port 1433")
        print("  - Wrong server hostname")
        print("  - SQL Server is down")
        print()
        print("WHAT TO DO:")
        print("  1. Verify you're on corporate VPN if working remotely")
        print("  2. Check with your DBA that the server name is correct")
        print(f"     You're trying to connect to: {SERVER}")
        print("  3. Ask DBA: 'Can you confirm the SQL Server is running?'")
        print("  4. Test from another system to isolate the issue")

    # ODBC Driver issues
    elif "driver" in error_str or "odbc" in error_str:
        print("🔍 DIAGNOSIS: ODBC Driver Issue")
        print("=" * 70)
        print()
        print("The ODBC driver is not installed or not found.")
        print()
        print("WHAT TO DO:")
        print("  1. Check available drivers:")
        print("     odbcinst -q -d")
        print()
        print("  2. Verify 'ODBC Driver 17 for SQL Server' or 'ODBC Driver 18' exists")
        print()
        print("  3. If missing, install in container:")
        print("     - Alpine: Check Dockerfile for ODBC installation")
        print("     - Debian: apt-get install msodbcsql17 or msodbcsql18")
        print()
        print("  4. Update connection string to match installed driver")
        print("     Current: DRIVER={{ODBC Driver 17 for SQL Server}}")

    # Authentication issues (non-SPN)
    elif "auth" in error_str or "kerberos" in error_str or "credential" in error_str:
        print("🔍 DIAGNOSIS: Kerberos Ticket Issue")
        print("=" * 70)
        print()
        print("Your Kerberos ticket is invalid or not being used correctly.")
        print()
        print("WHAT TO DO:")
        print("  1. Check ticket is valid:")
        print("     klist")
        print()
        print("  2. Verify ticket expiration time is in the future")
        print()
        print("  3. Check KRB5CCNAME is set correctly:")
        print(f"     Current: {krb5ccname}")
        print()
        print("  4. Get a fresh ticket on host:")
        print("     kinit your_username@DOMAIN.COM")
        print()
        print("  5. Restart the Kerberos sidecar:")
        print("     make platform-restart")
        print()
        print("  6. Run diagnostic:")
        print("     ./diagnose-kerberos.sh")

    # Generic database error
    elif "database" in error_str or "cannot open database" in error_str:
        print("🔍 DIAGNOSIS: Database Access Issue")
        print("=" * 70)
        print()
        print(f"Connected to server but cannot access database '{DATABASE}'")
        print()
        print("WHAT TO DO:")
        print("  1. Verify database name is correct:")
        print(f"     Current database: {DATABASE}")
        print()
        print("  2. Check if database exists (ask DBA):")
        print(f"     Does database '{DATABASE}' exist on {SERVER}?")
        print()
        print("  3. Verify you have permissions:")
        print("     Tell DBA: 'I need db_datareader access to {DATABASE}'")
        print()
        print("  4. Try a different database you know exists:")
        print("     SQL_DATABASE=master (or another accessible DB)")

    # Unknown error - provide best-effort guidance
    else:
        print("🔍 DIAGNOSIS: Unknown Error")
        print("=" * 70)
        print()
        print("The specific error is not recognized. Here's how to investigate:")
        print()
        print("STEP-BY-STEP TROUBLESHOOTING:")
        print()
        print("1. CHECK KERBEROS TICKET:")
        print("   klist")
        print("   - Should show valid ticket for your domain")
        print("   - Check expiration time is in the future")
        print()
        print("2. CHECK NETWORK:")
        print(f"   nc -zv {SERVER} 1433")
        print("   - Should connect successfully")
        print("   - If fails: check VPN, firewall, server name")
        print()
        print("3. CHECK ODBC DRIVER:")
        print("   odbcinst -q -d")
        print("   - Should list 'ODBC Driver 17 for SQL Server' or similar")
        print()
        print("4. CONTACT DBA WITH THIS INFO:")
        print("-" * 70)
        print(f"Server: {SERVER}")
        print(f"Database: {DATABASE}")
        print(f"Error: {e}")
        print("Authentication: Kerberos (Trusted_Connection=yes)")
        print("-" * 70)

    print()
    print("=" * 70)
    sys.exit(1)

except Exception as e:
    print(f"\n❌ Unexpected error: {e}")
    sys.exit(1)

print("\n🎉 Kerberos authentication is working perfectly!")
print("You're ready to use SQL Server with Astronomer!")
