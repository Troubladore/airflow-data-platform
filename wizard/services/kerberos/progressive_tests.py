"""Progressive Kerberos testing - from basic to advanced SQL connectivity.

This module provides increasingly complex tests to validate Kerberos functionality,
starting with basic ticket checks and progressing to SQL Server connections through
Docker containers.
"""

import os
import re
from typing import Dict, Any, List, Tuple, Optional
from wizard.services.kerberos.detection import KerberosDetector


class KerberosProgressiveTester:
    """Progressive testing of Kerberos capabilities."""

    def __init__(self, runner):
        """Initialize tester with action runner.

        Args:
            runner: ActionRunner for executing commands
        """
        self.runner = runner
        self.detector = KerberosDetector(runner)
        self.test_levels = []
        self.guidance = []

    def run_progressive_tests(self, ctx: Dict[str, Any]) -> Dict[str, Any]:
        """Run progressive Kerberos tests from basic to advanced.

        Tests get progressively more complex:
        Level 1: Basic Kerberos tools
        Level 2: Ticket validation
        Level 3: Cache sharing with containers
        Level 4: Container-to-container connectivity
        Level 5: SQL Server connectivity

        Args:
            ctx: Context with configuration

        Returns:
            Dict with test results and guidance
        """
        self.runner.display("\n🔬 Progressive Kerberos Testing")
        self.runner.display("=" * 50)
        self.runner.display("Testing from basic to advanced capabilities...\n")

        results = {
            'levels_passed': 0,
            'total_levels': 5,
            'highest_level': 0,
            'details': [],
            'guidance': [],
            'commands': []
        }

        # Level 1: Basic Kerberos Tools
        if self._test_level_1():
            results['levels_passed'] += 1
            results['highest_level'] = 1

            # Level 2: Ticket Validation
            if self._test_level_2(ctx):
                results['levels_passed'] += 2
                results['highest_level'] = 2

                # Level 3: Container Cache Sharing
                if self._test_level_3():
                    results['levels_passed'] += 1
                    results['highest_level'] = 3

                    # Level 4: Container-to-Container
                    if self._test_level_4():
                        results['levels_passed'] += 1
                        results['highest_level'] = 4

                        # Level 5: SQL Server Connectivity
                        if self._test_level_5(ctx):
                            results['levels_passed'] += 1
                            results['highest_level'] = 5

        # Provide summary and guidance
        self._provide_summary(results, ctx)
        return results

    def _test_level_1(self) -> bool:
        """Level 1: Test basic Kerberos tools availability."""
        self.runner.display("📊 Level 1: Basic Kerberos Tools")
        self.runner.display("-" * 40)

        tests_passed = 0
        tests_total = 3

        # Test klist
        result = self.runner.run_shell(['which', 'klist'])
        if result['returncode'] == 0:
            self.runner.display("  ✅ klist command found")
            tests_passed += 1
        else:
            self.runner.display("  ❌ klist not found")
            self._add_guidance(
                "Install Kerberos tools",
                "sudo apt-get install krb5-user",
                "Required for ticket management"
            )

        # Test kinit
        result = self.runner.run_shell(['which', 'kinit'])
        if result['returncode'] == 0:
            self.runner.display("  ✅ kinit command found")
            tests_passed += 1
        else:
            self.runner.display("  ❌ kinit not found")

        # Test kdestroy
        result = self.runner.run_shell(['which', 'kdestroy'])
        if result['returncode'] == 0:
            self.runner.display("  ✅ kdestroy command found")
            tests_passed += 1
        else:
            self.runner.display("  ❌ kdestroy not found")

        passed = tests_passed == tests_total
        status = "✅ PASSED" if passed else f"⚠️  PARTIAL ({tests_passed}/{tests_total})"
        self.runner.display(f"\nLevel 1 Result: {status}\n")
        return passed

    def _test_level_2(self, ctx: Dict[str, Any]) -> bool:
        """Level 2: Test ticket validation and cache format."""
        self.runner.display("📊 Level 2: Ticket Validation")
        self.runner.display("-" * 40)

        # Check for valid tickets
        result = self.runner.run_shell(['klist', '-s'])
        has_tickets = result['returncode'] == 0

        if has_tickets:
            self.runner.display("  ✅ Valid Kerberos tickets found")

            # Get ticket details
            klist_result = self.runner.run_shell(['klist'])
            if klist_result['returncode'] == 0:
                output = klist_result['stdout']

                # Parse and display ticket info
                principal_match = re.search(r'Default principal:\s*(.+)', output)
                if principal_match:
                    self.runner.display(f"     Principal: {principal_match.group(1)}")

                # Check expiry
                if 'Expires' in output:
                    self.runner.display("     Tickets are valid and not expired")

                # Check cache format
                cache_info = self.detector.detect_ticket_cache()
                if cache_info:
                    format = cache_info['format']
                    if format == 'KCM':
                        self.runner.display(f"  ⚠️  Using {format} format (needs conversion)")
                        self._add_guidance(
                            "Convert to FILE format for Docker",
                            "export KRB5CCNAME=FILE:/tmp/krb5cc_$(id -u)",
                            "Then run: kinit"
                        )
                        return False
                    else:
                        self.runner.display(f"  ✅ Using {format} format (Docker-compatible)")

                self.runner.display("\nLevel 2 Result: ✅ PASSED\n")
                return True
        else:
            self.runner.display("  ❌ No valid Kerberos tickets")

            domain = ctx.get('services.kerberos.domain', self.detector.detect_domain())
            if domain:
                self._add_guidance(
                    "Get Kerberos tickets",
                    f"kinit YOUR_USERNAME@{domain}",
                    "Required for authentication"
                )
            else:
                self._add_guidance(
                    "Get Kerberos tickets",
                    "kinit YOUR_USERNAME@YOUR_DOMAIN.COM",
                    "Required for authentication"
                )

            # Provide cache refresh guidance
            self._add_guidance(
                "Refresh expired tickets",
                "kdestroy && kinit",
                "Clears old tickets and gets new ones"
            )

            self.runner.display("\nLevel 2 Result: ❌ FAILED (no tickets)\n")
            return False

    def _test_level_3(self) -> bool:
        """Level 3: Test container cache sharing."""
        self.runner.display("📊 Level 3: Container Cache Sharing")
        self.runner.display("-" * 40)

        # Check if Docker is available
        docker_check = self.runner.run_shell(['docker', 'info'])
        if docker_check['returncode'] != 0:
            self.runner.display("  ❌ Docker not available")
            self._add_guidance(
                "Start Docker",
                "sudo systemctl start docker",
                "Required for container testing"
            )
            self.runner.display("\nLevel 3 Result: ❌ FAILED (no Docker)\n")
            return False

        # Check for platform network
        network_check = self.runner.run_shell([
            'docker', 'network', 'ls', '--format', '{{.Name}}', '--filter', 'name=platform_network'
        ])
        if 'platform_network' not in network_check.get('stdout', ''):
            self.runner.display("  ⚠️  Platform network missing")
            self._add_guidance(
                "Create platform network",
                "docker network create platform_network",
                "Required for container networking"
            )

        # Check for Kerberos cache volume
        volume_check = self.runner.run_shell([
            'docker', 'volume', 'ls', '--format', '{{.Name}}', '--filter', 'name=platform_kerberos_cache'
        ])
        if 'platform_kerberos_cache' not in volume_check.get('stdout', ''):
            self.runner.display("  ⚠️  Kerberos cache volume missing")
            self._add_guidance(
                "Create cache volume",
                "docker volume create platform_kerberos_cache",
                "Required for ticket sharing"
            )
        else:
            self.runner.display("  ✅ Kerberos cache volume exists")

        # Test ticket visibility in container
        test_result = self.runner.run_shell([
            'docker', 'run', '--rm',
            '--network', 'platform_network',
            '-v', 'platform_kerberos_cache:/krb5/cache:ro',
            'alpine:latest',
            'sh', '-c', 'ls -la /krb5/cache/ 2>/dev/null | grep -q krb5cc'
        ])

        if test_result['returncode'] == 0:
            self.runner.display("  ✅ Tickets visible in containers")
            self.runner.display("\nLevel 3 Result: ✅ PASSED\n")
            return True
        else:
            self.runner.display("  ❌ Tickets not visible in containers")
            self._add_guidance(
                "Copy tickets to volume",
                "docker run --rm -v platform_kerberos_cache:/cache -v /tmp:/host alpine cp /host/krb5cc_$(id -u) /cache/krb5cc",
                "Makes tickets available to containers"
            )
            self.runner.display("\nLevel 3 Result: ❌ FAILED\n")
            return False

    def _test_level_4(self) -> bool:
        """Level 4: Test container-to-container Kerberos."""
        self.runner.display("📊 Level 4: Container-to-Container Kerberos")
        self.runner.display("-" * 40)

        # Check if sidecar is running
        sidecar_check = self.runner.run_shell([
            'docker', 'ps', '--format', '{{.Names}}', '--filter', 'name=kerberos'
        ])

        sidecar_running = 'kerberos' in sidecar_check.get('stdout', '')

        if not sidecar_running:
            self.runner.display("  ⚠️  Kerberos sidecar not running")
            self._add_guidance(
                "Start Kerberos sidecar",
                "make kerberos-start",
                "Manages ticket lifecycle"
            )
            self.runner.display("\nLevel 4 Result: ⚠️  SKIPPED (no sidecar)\n")
            return False

        self.runner.display("  ✅ Kerberos sidecar running")

        # Test container can use shared tickets
        test_cmd = """
docker run --rm \
    --network platform_network \
    -v platform_kerberos_cache:/krb5/cache:ro \
    alpine:latest sh -c '
        apk add --no-cache krb5 >/dev/null 2>&1
        export KRB5CCNAME=/krb5/cache/krb5cc
        if klist -s 2>/dev/null; then
            echo "SUCCESS"
        else
            echo "FAILED"
        fi
    '
"""
        result = self.runner.run_shell(['bash', '-c', test_cmd])

        if 'SUCCESS' in result.get('stdout', ''):
            self.runner.display("  ✅ Container can use shared tickets")
            self.runner.display("\nLevel 4 Result: ✅ PASSED\n")
            return True
        else:
            self.runner.display("  ❌ Container cannot use shared tickets")
            self._add_guidance(
                "Debug ticket sharing",
                "docker exec kerberos-sidecar-mock klist",
                "Check if sidecar has tickets"
            )
            self.runner.display("\nLevel 4 Result: ❌ FAILED\n")
            return False

    def _test_level_5(self, ctx: Dict[str, Any]) -> bool:
        """Level 5: Test SQL Server connectivity."""
        self.runner.display("📊 Level 5: SQL Server Connectivity")
        self.runner.display("-" * 40)

        # Check if SQL server is configured
        sql_server = ctx.get('services.kerberos.sql_server')
        sql_database = ctx.get('services.kerberos.sql_database')

        if not sql_server:
            self.runner.display("  ℹ️  No SQL Server configured for testing")
            self._add_guidance(
                "Test SQL connectivity manually",
                "./kerberos/diagnostics/test-sql-simple.sh YOUR_SERVER YOUR_DB",
                "Validates end-to-end Kerberos auth"
            )
            self.runner.display("\nLevel 5 Result: ⏭️  SKIPPED (no SQL config)\n")
            return False

        self.runner.display(f"  Testing: {sql_server}/{sql_database}")

        # Quick connectivity check (without full SQL tools)
        nc_check = self.runner.run_shell([
            'nc', '-zv', '-w', '2', sql_server, '1433'
        ])

        if nc_check['returncode'] == 0:
            self.runner.display(f"  ✅ SQL Server {sql_server} is reachable")
            self._add_guidance(
                "Full SQL test with Kerberos",
                f"./kerberos/diagnostics/test-sql-simple.sh {sql_server} {sql_database}",
                "Complete end-to-end validation"
            )
            self.runner.display("\nLevel 5 Result: ✅ PASSED (connectivity)\n")
            return True
        else:
            self.runner.display(f"  ❌ Cannot reach {sql_server}:1433")
            self._add_guidance(
                "Check network connectivity",
                f"nslookup {sql_server}",
                "Verify DNS resolution"
            )
            self._add_guidance(
                "Test from corporate network",
                "Connect to VPN if required",
                "SQL Server may require corporate network"
            )
            self.runner.display("\nLevel 5 Result: ❌ FAILED (no connectivity)\n")
            return False

    def _add_guidance(self, action: str, command: str, reason: str):
        """Add guidance for user.

        Args:
            action: What to do
            command: Command to run
            reason: Why it's needed
        """
        self.guidance.append({
            'action': action,
            'command': command,
            'reason': reason
        })

    def _provide_summary(self, results: Dict[str, Any], ctx: Dict[str, Any]):
        """Provide summary and actionable guidance.

        Args:
            results: Test results
            ctx: Context
        """
        level = results['highest_level']

        self.runner.display("\n" + "=" * 50)
        self.runner.display("📈 Progressive Test Summary")
        self.runner.display("=" * 50)

        # Show progress bar
        progress = "█" * level + "░" * (5 - level)
        percentage = (level / 5) * 100
        self.runner.display(f"\nProgress: [{progress}] {percentage:.0f}%")
        self.runner.display(f"Highest Level Reached: {level}/5")

        # Describe what's working
        self.runner.display("\n✅ Working:")
        if level >= 1:
            self.runner.display("  • Basic Kerberos tools installed")
        if level >= 2:
            self.runner.display("  • Valid Kerberos tickets")
        if level >= 3:
            self.runner.display("  • Docker container cache sharing")
        if level >= 4:
            self.runner.display("  • Container-to-container Kerberos")
        if level >= 5:
            self.runner.display("  • SQL Server connectivity")

        # Provide next steps
        if self.guidance:
            self.runner.display("\n📋 Recommended Actions:")
            for i, guide in enumerate(self.guidance[:3], 1):  # Show top 3
                self.runner.display(f"\n  {i}. {guide['action']}")
                self.runner.display(f"     Command: {guide['command']}")
                self.runner.display(f"     Reason: {guide['reason']}")

        # Diagnostic commands based on level
        self.runner.display("\n🔧 Diagnostic Commands:")
        self.runner.display("\n  Check current status:")
        self.runner.display("    klist              # View current tickets")
        self.runner.display("    klist -e           # View encryption types")

        if level < 2:
            self.runner.display("\n  Get tickets:")
            domain = ctx.get('services.kerberos.domain', 'DOMAIN.COM')
            self.runner.display(f"    kinit user@{domain}  # Get new ticket")
            self.runner.display("    kdestroy           # Clear old tickets")

        if level >= 2 and level < 4:
            self.runner.display("\n  Test container integration:")
            self.runner.display("    docker exec kerberos-sidecar-mock klist")
            self.runner.display("    docker logs kerberos-sidecar-mock --tail 20")

        if level >= 3:
            self.runner.display("\n  Advanced testing:")
            self.runner.display("    ./kerberos/diagnostics/diagnose-kerberos.sh")
            if level >= 4:
                self.runner.display("    ./kerberos/diagnostics/test-sql-simple.sh SERVER DB")
                self.runner.display("    ./kerberos/diagnostics/check-sql-spn.sh SERVER")

        # Cache management
        self.runner.display("\n🔄 Cache Management:")
        self.runner.display("  kdestroy && kinit    # Refresh tickets")
        self.runner.display("  klist -A             # List all caches")

        cache_info = self.detector.detect_ticket_cache()
        if cache_info and cache_info.get('directory'):
            self.runner.display(f"  ls -la {cache_info['directory']}  # Check cache files")

        # Platform-specific guidance
        if self.detector._is_wsl2():
            self.runner.display("\n💡 WSL2 Tips:")
            self.runner.display("  • Ensure Windows has valid domain tickets")
            self.runner.display("  • May need to sync time: sudo hwclock -s")
            self.runner.display("  • Check Windows tickets: powershell.exe klist")

        # Success message
        if level == 5:
            self.runner.display("\n🎉 Congratulations! Full Kerberos stack is working!")
            self.runner.display("   You can now use Kerberos authentication with SQL Server")
            self.runner.display("   and other services in your Docker containers.")
        elif level > 0:
            self.runner.display(f"\n💪 Good progress! Level {level}/5 achieved.")
            self.runner.display("   Follow the recommendations above to reach the next level.")
        else:
            self.runner.display("\n🚀 Let's get started! Follow the steps above to enable Kerberos.")

        results['guidance'] = self.guidance


def run_progressive_tests(ctx: Dict[str, Any], runner) -> None:
    """Action to run progressive Kerberos tests.

    Args:
        ctx: Context dictionary
        runner: ActionRunner instance
    """
    tester = KerberosProgressiveTester(runner)
    results = tester.run_progressive_tests(ctx)

    # Store results in context
    ctx['services.kerberos.progressive_test_results'] = results
    ctx['services.kerberos.highest_level'] = results['highest_level']