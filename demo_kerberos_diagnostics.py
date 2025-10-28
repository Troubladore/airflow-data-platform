#!/usr/bin/env python3
"""
Demonstration of Kerberos diagnostic and guidance capabilities.

Shows how the system provides comprehensive diagnostic commands,
cache management guidance, and progressive testing to help users
troubleshoot and verify their Kerberos setup.
"""

import sys
from pathlib import Path

# Add parent to path
sys.path.insert(0, str(Path(__file__).parent))

from wizard.services.kerberos.detection import KerberosDetector
from wizard.services.kerberos.progressive_tests import KerberosProgressiveTester


class MockRunner:
    """Mock runner for demonstration."""

    def __init__(self, verbose=True):
        self.displayed = []
        self.verbose = verbose

    def display(self, msg):
        if self.verbose:
            print(msg)
        self.displayed.append(msg)

    def run_shell(self, cmd, **kwargs):
        # Simulate command execution
        import subprocess
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            return {
                'returncode': result.returncode,
                'stdout': result.stdout,
                'stderr': result.stderr
            }
        except:
            return {'returncode': 1, 'stdout': '', 'stderr': 'Command failed'}


def section(title):
    """Print a section header."""
    print("\n" + "="*70)
    print(f"  {title}")
    print("="*70)


def demo_wizard_experience():
    """Show the new wizard experience with section headers."""
    section("WIZARD EXPERIENCE WITH CLEAR SECTIONS")

    print("""
Previous Experience:
--------------------
Enter PostgreSQL password: ****
Enter Kerberos domain (e.g., COMPANY.COM): [user types domain]
⚠ Kerberos test skipped (will configure on first use)
Enter next service configuration...

[No clear boundaries between services]
""")

    print("""
New Experience:
---------------""")

    runner = MockRunner(verbose=False)
    ctx = {}

    # Simulate detection action
    from wizard.services.kerberos.actions import detect_configuration
    detect_configuration(ctx, runner)

    # Show first few lines
    for line in runner.displayed[:8]:
        print(line)

    print("\n[Auto-detection runs here...]")
    print("\nThe wizard now clearly shows:")
    print("  ✅ Section start with clear header")
    print("  ✅ What service is being configured")
    print("  ✅ Auto-detection results before prompting")
    print("  ✅ Section completion summary")


def demo_progressive_testing():
    """Demonstrate progressive testing capabilities."""
    section("PROGRESSIVE TESTING CAPABILITIES")

    print("\nThe system now tests Kerberos progressively:\n")

    runner = MockRunner()
    ctx = {'services.kerberos.domain': 'COMPANY.COM'}

    tester = KerberosProgressiveTester(runner)

    # Show what progressive testing looks like
    print("Sample Progressive Test Output:")
    print("-" * 50)

    # Simulate partial success
    print("""
📊 Level 1: Basic Kerberos Tools
----------------------------------------
  ✅ klist command found
  ✅ kinit command found
  ✅ kdestroy command found

Level 1 Result: ✅ PASSED

📊 Level 2: Ticket Validation
----------------------------------------
  ❌ No valid Kerberos tickets

Level 2 Result: ❌ FAILED (no tickets)

==================================================
📈 Progressive Test Summary
==================================================

Progress: [██░░░] 40%
Highest Level Reached: 2/5

✅ Working:
  • Basic Kerberos tools installed

📋 Recommended Actions:

  1. Get Kerberos tickets
     Command: kinit YOUR_USERNAME@COMPANY.COM
     Reason: Required for authentication
""")


def demo_diagnostic_commands():
    """Show all diagnostic commands and guidance."""
    section("COMPREHENSIVE DIAGNOSTIC COMMANDS")

    print("""
The system provides context-aware diagnostic commands:

🔧 Basic Diagnostics:
---------------------
  klist                    # View current tickets
  klist -e                 # View encryption types
  klist -A                 # List all ticket caches
  klist -s                 # Silent check (for scripts)

🔄 Cache Management:
--------------------
  kdestroy                 # Clear all tickets
  kinit user@DOMAIN        # Get new ticket
  kdestroy && kinit        # Refresh tickets

  # Convert KCM to FILE format for Docker:
  export KRB5CCNAME=FILE:/tmp/krb5cc_$(id -u)
  kinit

📦 Container Diagnostics:
------------------------
  # Check sidecar tickets:
  docker exec kerberos-sidecar-mock klist

  # View sidecar logs:
  docker logs kerberos-sidecar-mock --tail 20

  # Test cache sharing:
  docker run --rm \\
    -v platform_kerberos_cache:/cache:ro \\
    alpine ls -la /cache/

🔍 Advanced Diagnostics:
------------------------
  # Full system diagnostic:
  ./kerberos/diagnostics/diagnose-kerberos.sh

  # Test SQL connectivity:
  ./kerberos/diagnostics/test-sql-simple.sh SERVER DB

  # Check SQL Server SPNs:
  ./kerberos/diagnostics/check-sql-spn.sh SERVER

  # Direct SQL test (bypasses sidecar):
  ./kerberos/diagnostics/test-sql-direct.sh SERVER DB
""")


def demo_error_guidance():
    """Show how the system provides specific error guidance."""
    section("INTELLIGENT ERROR GUIDANCE")

    print("""
The system analyzes errors and provides specific fixes:

Example 1: No Tickets
---------------------
  ❌ No valid Kerberos tickets

  Guidance provided:
    • Run: kinit YOUR_USERNAME@DETECTED_DOMAIN.COM
    • Domain was auto-detected as DETECTED_DOMAIN.COM
    • Check ticket status with: klist

Example 2: KCM Format (Docker Incompatible)
-------------------------------------------
  ⚠️ KCM format detected - needs conversion for Docker

  Guidance provided:
    • Run: export KRB5CCNAME=FILE:/tmp/krb5cc_$(id -u)
    • Then: kinit YOUR_USERNAME@DOMAIN.COM
    • This converts to Docker-compatible format

Example 3: SQL Connection Timeout
---------------------------------
  ❌ Connection failed: Login timeout expired

  Guidance provided:
    • Test direct connectivity: ./test-sql-direct.sh SERVER DB
    • Check DNS resolution: nslookup SERVER
    • Test network: telnet SERVER 1433
    • Verify VPN connection if required

Example 4: Kerberos Auth Failed
-------------------------------
  ❌ Cannot authenticate using Kerberos

  Guidance provided:
    • Ask DBA to verify SPNs: setspn -L <service-account>
    • Check clock sync: timedatectl status
    • Verify ticket: klist -e
""")


def demo_platform_specific():
    """Show platform-specific guidance."""
    section("PLATFORM-SPECIFIC GUIDANCE")

    detector = KerberosDetector()

    print(f"\nCurrent Platform: {'WSL2' if detector._is_wsl2() else 'Native Linux'}")

    print("""
WSL2-Specific Guidance:
-----------------------
  • Check Windows tickets: powershell.exe klist
  • Sync time: sudo hwclock -s
  • Get Windows domain: powershell.exe -Command "$env:USERDNSDOMAIN"
  • Share tickets from Windows: wsl-kerberos-ticket-share.sh

Native Linux Guidance:
----------------------
  • Join domain: realm join DOMAIN.COM
  • Check sssd: systemctl status sssd
  • Update krb5.conf: /etc/krb5.conf

macOS Guidance:
---------------
  • Use Ticket Viewer.app
  • Configure: /Library/Preferences/edu.mit.Kerberos
  • Get tickets: kinit -l 10h (longer lifetime)
""")


def demo_cache_locations():
    """Show how the system handles different cache locations."""
    section("CACHE LOCATION DETECTION")

    print("""
The system auto-detects various ticket cache formats:

FILE Format:
-----------
  Detected: FILE:/tmp/krb5cc_1000
  Docker mount: -v /tmp:/krb5/cache:ro

DIR Format (Collection):
------------------------
  Detected: DIR::/home/user/.krb5-cache/
  Auto-finds active ticket in subdirectories
  Docker mount: -v /home/user/.krb5-cache:/krb5/cache:ro

KCM Format:
-----------
  Detected: KCM:
  Provides conversion instructions
  Not directly shareable with Docker

The wizard automatically:
  ✅ Detects your cache location
  ✅ Determines the base directory for Docker
  ✅ Provides exact mount commands
  ✅ Handles complex paths (with spaces, etc.)
""")


def demo_sql_testing():
    """Show SQL Server testing capabilities."""
    section("SQL SERVER TESTING PROGRESSION")

    print("""
Progressive SQL Testing:
------------------------

Level 1: Network Connectivity
  • Test: nc -zv SERVER 1433
  • Verifies: Can reach SQL Server

Level 2: DNS Resolution
  • Test: nslookup _kerberos._tcp.domain.com
  • Verifies: Domain services available

Level 3: Direct Kerberos Test
  • Test: kvno MSSQLSvc/server:1433
  • Verifies: Can get service ticket

Level 4: Container SQL Test
  • Test: docker run ... sqlcmd -E
  • Verifies: Container can authenticate

Level 5: Full Integration
  • Test: Through sidecar to remote SQL
  • Verifies: Complete stack works

Each level failure provides:
  • Specific error analysis
  • Targeted fix commands
  • Alternative test approaches
""")


def demo_summary():
    """Show summary of all diagnostic capabilities."""
    section("COMPLETE DIAGNOSTIC CAPABILITIES")

    print("""
The Enhanced Kerberos System Provides:

1. 🔍 Auto-Detection
   - Domain from multiple sources
   - Ticket cache location and format
   - Principal and ticket status
   - Platform-specific settings

2. 📊 Progressive Testing
   - 5 levels from basic to SQL
   - Clear indication of capabilities
   - Specific guidance per level

3. 🛠️ Diagnostic Commands
   - Cache management (refresh, clear, convert)
   - Container verification
   - SQL connectivity tests
   - Platform-specific tools

4. 📋 Intelligent Guidance
   - Error-specific solutions
   - Context-aware commands
   - Platform-specific tips
   - Next-step recommendations

5. 🎯 Clear User Experience
   - Section headers for clarity
   - Progress indicators
   - Success/failure summaries
   - Quick reference commands

Result: Users can diagnose and fix Kerberos issues independently
        with clear, actionable guidance at every step!
""")


def main():
    """Run all demonstrations."""
    print("\n" + "🔐"*35)
    print("   KERBEROS DIAGNOSTIC & GUIDANCE DEMONSTRATION")
    print("🔐"*35)

    demo_wizard_experience()
    demo_progressive_testing()
    demo_diagnostic_commands()
    demo_error_guidance()
    demo_platform_specific()
    demo_cache_locations()
    demo_sql_testing()
    demo_summary()

    print("\n✨ The system now provides comprehensive diagnostic")
    print("   capabilities with clear, actionable guidance!")
    print()


if __name__ == "__main__":
    main()