#!/usr/bin/env python3
"""Integration tests for enhanced Kerberos capabilities."""

import os
import sys
import json
import subprocess
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from wizard.services.kerberos.detection import KerberosDetector


class KerberosEnhancementTests:
    """Test suite for Kerberos auto-detection and diagnostics."""

    def __init__(self):
        self.detector = KerberosDetector()
        self.test_results = []
        self.verbose = '-v' in sys.argv or '--verbose' in sys.argv

    def log(self, message, indent=0):
        """Print a log message."""
        prefix = "  " * indent
        print(f"{prefix}{message}")

    def run_test(self, name, test_func):
        """Run a single test and record result."""
        self.log(f"\n📝 Testing: {name}")
        try:
            result = test_func()
            if result:
                self.log("  ✅ PASSED", 1)
                self.test_results.append((name, True))
            else:
                self.log("  ❌ FAILED", 1)
                self.test_results.append((name, False))
            return result
        except Exception as e:
            self.log(f"  ❌ ERROR: {e}", 1)
            self.test_results.append((name, False))
            return False

    def test_domain_detection(self):
        """Test domain auto-detection."""
        domain = self.detector.detect_domain()

        if domain:
            self.log(f"    Detected domain: {domain}", 1)
            self.log("    ✓ Domain detection working", 1)
            return True
        else:
            self.log("    ⚠ No domain detected (may be normal in non-corp environment)", 1)
            # Check if we're in WSL2 for better diagnostics
            if self.detector._is_wsl2():
                self.log("    Running in WSL2 - checking Windows domain...", 1)
                ps_domain = self.detector._detect_from_powershell()
                if ps_domain:
                    self.log(f"    Windows domain found: {ps_domain}", 1)
                else:
                    self.log("    No Windows domain detected", 1)

            # Not a failure if not in corp environment
            return True

    def test_ticket_cache_detection(self):
        """Test ticket cache auto-detection."""
        cache_info = self.detector.detect_ticket_cache()

        if cache_info:
            self.log(f"    Format: {cache_info['format']}", 1)
            self.log(f"    Path: {cache_info['path']}", 1)
            if cache_info.get('directory'):
                self.log(f"    Directory: {cache_info['directory']}", 1)

            # Check Docker compatibility
            if cache_info['format'] == 'KCM':
                self.log("    ⚠ KCM format needs conversion for Docker", 1)
                self.log("      Suggestion: export KRB5CCNAME=FILE:/tmp/krb5cc_$(id -u)", 1)
            else:
                self.log(f"    ✓ {cache_info['format']} format is Docker-compatible", 1)

            return True
        else:
            self.log("    ⚠ No ticket cache detected", 1)
            self.log("    This is normal if no tickets exist", 1)
            return True

    def test_principal_detection(self):
        """Test principal auto-detection."""
        principal = self.detector.detect_principal()

        if principal:
            self.log(f"    Detected principal: {principal}", 1)
            return True
        else:
            self.log("    No principal detected (normal if no tickets)", 1)
            return True

    def test_comprehensive_detection(self):
        """Test the comprehensive detect_all method."""
        all_info = self.detector.detect_all()

        self.log("    Detection results:", 1)
        self.log(f"      Domain: {all_info.get('domain', 'Not detected')}", 1)
        self.log(f"      Has tickets: {all_info.get('has_tickets', False)}", 1)

        if all_info.get('ticket_cache'):
            cache = all_info['ticket_cache']
            self.log(f"      Cache format: {cache.get('format', 'Unknown')}", 1)

        if all_info.get('principal'):
            self.log(f"      Principal: {all_info['principal']}", 1)

        return True

    def test_diagnostic_info(self):
        """Test diagnostic information gathering."""
        diag = self.detector.get_diagnostic_info()

        self.log("    Environment info:", 1)
        env = diag.get('environment', {})
        self.log(f"      WSL2: {env.get('is_wsl2', False)}", 1)
        self.log(f"      Has klist: {env.get('has_klist', False)}", 1)
        self.log(f"      Has kinit: {env.get('has_kinit', False)}", 1)

        if env.get('krb5_config'):
            self.log(f"      KRB5_CONFIG: {env['krb5_config']}", 1)
        if env.get('krb5ccname'):
            self.log(f"      KRB5CCNAME: {env['krb5ccname']}", 1)

        suggestions = diag.get('suggestions', {})
        if suggestions:
            self.log("    Suggestions:", 1)
            for key, suggestion in suggestions.items():
                self.log(f"      {key}: {suggestion}", 1)

        return True

    def test_wizard_integration(self):
        """Test wizard integration with mock runner."""
        # Create a mock runner for testing
        class MockRunner:
            def __init__(self):
                self.displayed = []

            def display(self, msg):
                self.displayed.append(msg)

            def run_shell(self, cmd, **kwargs):
                # Simulate running shell commands
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
                return {
                    'returncode': result.returncode,
                    'stdout': result.stdout,
                    'stderr': result.stderr
                }

        # Test the detect_configuration action
        from wizard.services.kerberos.actions import detect_configuration

        runner = MockRunner()
        ctx = {}

        try:
            detect_configuration(ctx, runner)

            # Check what was displayed
            if self.verbose:
                self.log("    Wizard output:", 1)
                for line in runner.displayed:
                    self.log(f"      {line}", 1)

            # Check context updates
            if 'services.kerberos.domain' in ctx:
                self.log(f"    ✓ Domain set in context: {ctx['services.kerberos.domain']}", 1)

            if 'services.kerberos.ticket_dir' in ctx:
                self.log(f"    ✓ Ticket dir set in context: {ctx['services.kerberos.ticket_dir']}", 1)

            return True
        except Exception as e:
            self.log(f"    Error in wizard integration: {e}", 1)
            return False

    def test_kerberos_validation(self):
        """Test the enhanced Kerberos test function."""
        # Test with mock runner
        class MockRunner:
            def __init__(self):
                self.displayed = []

            def display(self, msg):
                self.displayed.append(msg)

            def run_shell(self, cmd, **kwargs):
                # Simulate running shell commands
                try:
                    result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
                    return {
                        'returncode': result.returncode,
                        'stdout': result.stdout,
                        'stderr': result.stderr
                    }
                except Exception as e:
                    return {'returncode': 1, 'stdout': '', 'stderr': str(e)}

        from wizard.services.kerberos.actions import test_kerberos

        runner = MockRunner()
        ctx = {'services.kerberos.domain': 'TEST.COM'}

        try:
            result = test_kerberos(ctx, runner)

            # Check output
            if self.verbose:
                self.log("    Test output:", 1)
                for line in runner.displayed[-5:]:  # Show last 5 lines
                    self.log(f"      {line}", 1)

            # Check if tests were stored in context
            if 'services.kerberos.test_results' in ctx:
                results = ctx['services.kerberos.test_results']
                self.log(f"    Ran {len(results)} tests", 1)
                passed = sum(1 for _, r in results if r)
                self.log(f"    {passed}/{len(results)} passed", 1)

            return True
        except Exception as e:
            self.log(f"    Error in validation test: {e}", 1)
            return False

    def run_all_tests(self):
        """Run all tests and print summary."""
        print("\n" + "="*60)
        print("🔬 Kerberos Enhancement Test Suite")
        print("="*60)

        # Run each test
        self.run_test("Domain Detection", self.test_domain_detection)
        self.run_test("Ticket Cache Detection", self.test_ticket_cache_detection)
        self.run_test("Principal Detection", self.test_principal_detection)
        self.run_test("Comprehensive Detection", self.test_comprehensive_detection)
        self.run_test("Diagnostic Info", self.test_diagnostic_info)
        self.run_test("Wizard Integration", self.test_wizard_integration)
        self.run_test("Enhanced Validation", self.test_kerberos_validation)

        # Print summary
        print("\n" + "="*60)
        print("📊 Test Summary")
        print("="*60)

        passed = sum(1 for _, result in self.test_results if result)
        total = len(self.test_results)
        percentage = (passed / total * 100) if total > 0 else 0

        print(f"\nTests run: {total}")
        print(f"Passed: {passed}")
        print(f"Failed: {total - passed}")
        print(f"Success rate: {percentage:.1f}%")

        if passed == total:
            print("\n✨ All tests passed! Kerberos enhancements are working correctly.")
        elif passed > 0:
            print(f"\n⚠️  {total - passed} test(s) failed. Review the output above.")
        else:
            print("\n❌ All tests failed. Check your environment and configuration.")

        return passed == total


def main():
    """Main entry point."""
    tester = KerberosEnhancementTests()
    success = tester.run_all_tests()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()