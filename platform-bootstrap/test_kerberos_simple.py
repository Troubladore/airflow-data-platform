#!/usr/bin/env python3
"""
Simple test to verify Kerberos tickets are available in Docker containers.
This doesn't require SQL Server - just validates the ticket sharing works.
"""

import os
import subprocess

print("🔍 Checking Kerberos Ticket Availability in Docker Container")
print("=" * 60)

# Check environment
krb5ccname = os.environ.get("KRB5CCNAME")
if krb5ccname:
    print(f"✓ KRB5CCNAME is set: {krb5ccname}")

    # Check if the file exists
    if os.path.exists(krb5ccname):
        print(f"✓ Ticket cache file exists at {krb5ccname}")

        # Get file info
        stat_info = os.stat(krb5ccname)
        print(f"  Size: {stat_info.st_size} bytes")

        # Try to run klist
        try:
            result = subprocess.run(["klist"], capture_output=True, text=True)
            if result.returncode == 0:
                print("\n✓ Kerberos tickets found:")
                # Show first few lines of klist output
                lines = result.stdout.split("\n")
                for line in lines[:8]:  # Show first 8 lines
                    if line.strip():
                        print(f"  {line}")
                print("\n✅ SUCCESS! Kerberos tickets are accessible in the container!")
                print("   Your ticket sharing is working correctly.")
            else:
                print("✗ klist failed - no valid tickets")
                print(f"  Error: {result.stderr}")
        except FileNotFoundError:
            print("⚠️  klist command not found")
            print("   Install with: apk add krb5 (Alpine) or apt-get install krb5-user (Debian)")
    else:
        print(f"✗ Ticket cache file does NOT exist at {krb5ccname}")
        print("  The ticket sharing might not be working correctly")
else:
    print("✗ KRB5CCNAME environment variable is not set")
    print("  This should be set to: /krb5/cache/krb5cc")
    print("  Make sure you're running this with the correct Docker options")

print("\n" + "=" * 60)
print("📝 Next Steps:")
if krb5ccname and os.path.exists(krb5ccname):
    print("✓ Your setup is working! You can now:")
    print("  1. Run the SQL Server test: python test_kerberos.py")
    print("  2. Use Kerberos auth in your Airflow DAGs")
else:
    print("✗ Fix the issues above, then try again")
    print("  Make sure you:")
    print("  1. Have a valid ticket (run 'klist' on your host)")
    print("  2. Started platform services ('make platform-start')")
    print("  3. Are using the correct Docker volume mount")
