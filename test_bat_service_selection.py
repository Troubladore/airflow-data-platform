"""
Business Acceptance Testing for Task 23: Service Selection Interactive Mode

Tests the service selection experience from an end-user perspective.
"""

import sys
from pathlib import Path

# Add wizard to path
sys.path.insert(0, str(Path(__file__).parent))

from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


def print_header(title):
    """Print a formatted test section header."""
    print("\n" + "=" * 80)
    print(f" {title}")
    print("=" * 80 + "\n")


def print_result(label, value):
    """Print a formatted result."""
    print(f"  {label}: {value}")


def test_scenario_1_multiple_services():
    """Scenario 1: Select Multiple Services (openmetadata kerberos)"""
    print_header("SCENARIO 1: Select Multiple Services")

    runner = MockActionRunner()
    runner.input_queue = [
        'openmetadata kerberos',  # User types this
        '', '', '', '', ''         # Accept postgres defaults
    ]

    engine = WizardEngine(runner=runner, base_path='wizard')
    engine.execute_flow('setup')

    # Check results
    print("\nResults:")
    print_result("Postgres enabled", engine.state.get('services.postgres.enabled'))
    print_result("OpenMetadata enabled", engine.state.get('services.openmetadata.enabled'))
    print_result("Kerberos enabled", engine.state.get('services.kerberos.enabled'))
    print_result("Pagila enabled", engine.state.get('services.pagila.enabled'))
    print_result("Selected services", engine.state.get('selected_services'))

    # Check prompts
    print("\nPrompt Analysis:")
    selection_prompts = [c for c in runner.calls if c[0] == 'get_input' and 'Select services' in c[1]]
    print_result("Service selection prompt shown", len(selection_prompts) > 0)
    if selection_prompts:
        print(f"\n  Prompt text: \"{selection_prompts[0][1]}\"")

    # Check what options were displayed
    display_calls = [c for c in runner.calls if c[0] == 'display']
    print(f"\n  Options displayed to user:")
    for call in display_calls[:10]:  # Show first 10 display calls
        if 'openmetadata' in call[1].lower() or 'kerberos' in call[1].lower() or 'pagila' in call[1].lower():
            print(f"    {call[1]}")

    # Validation
    errors = []
    if not engine.state.get('services.postgres.enabled'):
        errors.append("Postgres should always be enabled")
    if not engine.state.get('services.openmetadata.enabled'):
        errors.append("OpenMetadata should be enabled")
    if not engine.state.get('services.kerberos.enabled'):
        errors.append("Kerberos should be enabled")
    if engine.state.get('services.pagila.enabled'):
        errors.append("Pagila should NOT be enabled")

    print("\nValidation:")
    if errors:
        print("  FAILED:")
        for error in errors:
            print(f"    - {error}")
    else:
        print("  PASSED: All services correctly enabled/disabled")

    return len(errors) == 0


def test_scenario_2_single_service():
    """Scenario 2: Select One Service (pagila)"""
    print_header("SCENARIO 2: Select One Service")

    runner = MockActionRunner()
    runner.input_queue = [
        'pagila',  # User types this
        '', '', '', '', ''  # Postgres defaults
    ]

    engine = WizardEngine(runner=runner, base_path='wizard')
    engine.execute_flow('setup')

    # Check results
    print("\nResults:")
    print_result("Postgres enabled", engine.state.get('services.postgres.enabled'))
    print_result("OpenMetadata enabled", engine.state.get('services.openmetadata.enabled'))
    print_result("Kerberos enabled", engine.state.get('services.kerberos.enabled'))
    print_result("Pagila enabled", engine.state.get('services.pagila.enabled'))
    print_result("Selected services", engine.state.get('selected_services'))

    # Validation
    errors = []
    if not engine.state.get('services.postgres.enabled'):
        errors.append("Postgres should always be enabled")
    if engine.state.get('services.openmetadata.enabled'):
        errors.append("OpenMetadata should NOT be enabled")
    if engine.state.get('services.kerberos.enabled'):
        errors.append("Kerberos should NOT be enabled")
    if not engine.state.get('services.pagila.enabled'):
        errors.append("Pagila should be enabled")

    print("\nValidation:")
    if errors:
        print("  FAILED:")
        for error in errors:
            print(f"    - {error}")
    else:
        print("  PASSED: Only pagila and postgres enabled")

    return len(errors) == 0


def test_scenario_3_no_additional_services():
    """Scenario 3: Select No Additional Services (just postgres)"""
    print_header("SCENARIO 3: Select No Additional Services")

    runner = MockActionRunner()
    runner.input_queue = [
        '',  # Empty input = just postgres
        '', '', '', '', ''  # Postgres defaults
    ]

    engine = WizardEngine(runner=runner, base_path='wizard')
    engine.execute_flow('setup')

    # Check results
    print("\nResults:")
    print_result("Postgres enabled", engine.state.get('services.postgres.enabled'))
    print_result("OpenMetadata enabled", engine.state.get('services.openmetadata.enabled'))
    print_result("Kerberos enabled", engine.state.get('services.kerberos.enabled'))
    print_result("Pagila enabled", engine.state.get('services.pagila.enabled'))
    print_result("Selected services", engine.state.get('selected_services'))

    # Validation
    errors = []
    if not engine.state.get('services.postgres.enabled'):
        errors.append("Postgres should always be enabled")
    if engine.state.get('services.openmetadata.enabled'):
        errors.append("OpenMetadata should NOT be enabled")
    if engine.state.get('services.kerberos.enabled'):
        errors.append("Kerberos should NOT be enabled")
    if engine.state.get('services.pagila.enabled'):
        errors.append("Pagila should NOT be enabled")

    print("\nValidation:")
    if errors:
        print("  FAILED:")
        for error in errors:
            print(f"    - {error}")
    else:
        print("  PASSED: Only postgres enabled")

    return len(errors) == 0


def test_scenario_4_typo_in_service_name():
    """Scenario 4: Typo in Service Name"""
    print_header("SCENARIO 4: Typo in Service Name")

    runner = MockActionRunner()
    runner.input_queue = [
        'openmedata',  # Typo! Should be 'openmetadata'
        '', '', '', '', ''  # Postgres defaults
    ]

    try:
        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Check results
        print("\nResults:")
        print_result("Postgres enabled", engine.state.get('services.postgres.enabled'))
        print_result("OpenMetadata enabled", engine.state.get('services.openmetadata.enabled'))
        print_result("Kerberos enabled", engine.state.get('services.kerberos.enabled'))
        print_result("Pagila enabled", engine.state.get('services.pagila.enabled'))
        print_result("Selected services", engine.state.get('selected_services'))

        print("\nBehavior Analysis:")
        print("  Wizard completed without errors")
        print("  Typo was silently ignored (service not enabled)")

        # Check if typo was silently ignored
        if 'openmedata' in engine.state.get('selected_services', []):
            print("\n  WARNING: Typo was stored in selected_services")
            print("  This is confusing - user thinks they selected a service")

        # UX Issues
        print("\nUX Assessment:")
        print("  ISSUE: Silent failure - user may not realize they made a typo")
        print("  SUGGESTION: Show available options OR validate service names")
        print("  SUGGESTION: Display confirmation of what will be installed")

        return False  # This is a UX issue even if it doesn't crash

    except Exception as e:
        print(f"\nError occurred: {type(e).__name__}: {e}")
        print("\nBehavior Analysis:")
        print("  Wizard crashed on typo - this is bad UX")
        print("  CRITICAL: Should handle invalid service names gracefully")
        return False


def test_scenario_5_all_services():
    """Scenario 5: Select All Services"""
    print_header("SCENARIO 5: Select All Services")

    runner = MockActionRunner()
    runner.input_queue = [
        'openmetadata kerberos pagila',  # All services
        '', '', '', '', ''  # Postgres defaults
    ]

    engine = WizardEngine(runner=runner, base_path='wizard')
    engine.execute_flow('setup')

    # Check results
    print("\nResults:")
    print_result("Postgres enabled", engine.state.get('services.postgres.enabled'))
    print_result("OpenMetadata enabled", engine.state.get('services.openmetadata.enabled'))
    print_result("Kerberos enabled", engine.state.get('services.kerberos.enabled'))
    print_result("Pagila enabled", engine.state.get('services.pagila.enabled'))
    print_result("Selected services", engine.state.get('selected_services'))

    # Validation
    errors = []
    if not engine.state.get('services.postgres.enabled'):
        errors.append("Postgres should be enabled")
    if not engine.state.get('services.openmetadata.enabled'):
        errors.append("OpenMetadata should be enabled")
    if not engine.state.get('services.kerberos.enabled'):
        errors.append("Kerberos should be enabled")
    if not engine.state.get('services.pagila.enabled'):
        errors.append("Pagila should be enabled")

    print("\nValidation:")
    if errors:
        print("  FAILED:")
        for error in errors:
            print(f"    - {error}")
    else:
        print("  PASSED: All services enabled")

    return len(errors) == 0


def test_scenario_6_comma_separated():
    """Scenario 6: User tries comma-separated instead of space-separated"""
    print_header("SCENARIO 6: Comma-Separated Input (Testing Parser)")

    runner = MockActionRunner()
    runner.input_queue = [
        'openmetadata,kerberos',  # User uses commas instead of spaces
        '', '', '', '', ''  # Postgres defaults
    ]

    engine = WizardEngine(runner=runner, base_path='wizard')
    engine.execute_flow('setup')

    # Check results
    print("\nResults:")
    print_result("Postgres enabled", engine.state.get('services.postgres.enabled'))
    print_result("OpenMetadata enabled", engine.state.get('services.openmetadata.enabled'))
    print_result("Kerberos enabled", engine.state.get('services.kerberos.enabled'))
    print_result("Pagila enabled", engine.state.get('services.pagila.enabled'))
    print_result("Selected services", engine.state.get('selected_services'))

    print("\nBehavior Analysis:")
    if engine.state.get('services.openmetadata.enabled') and engine.state.get('services.kerberos.enabled'):
        print("  Parser handled comma separation correctly")
        return True
    else:
        print("  Parser did NOT handle comma separation")
        print("  This could confuse users coming from CSV backgrounds")
        print("  SUGGESTION: Support both space and comma separation")
        return False


def main():
    """Run all test scenarios and generate report."""
    print("\n")
    print("╔" + "=" * 78 + "╗")
    print("║" + " BUSINESS ACCEPTANCE TESTING: Service Selection Interactive Mode ".center(78) + "║")
    print("╚" + "=" * 78 + "╝")

    results = {}

    # Run all scenarios
    try:
        results['scenario_1'] = test_scenario_1_multiple_services()
    except Exception as e:
        print(f"\nSCENARIO 1 CRASHED: {e}")
        results['scenario_1'] = False

    try:
        results['scenario_2'] = test_scenario_2_single_service()
    except Exception as e:
        print(f"\nSCENARIO 2 CRASHED: {e}")
        results['scenario_2'] = False

    try:
        results['scenario_3'] = test_scenario_3_no_additional_services()
    except Exception as e:
        print(f"\nSCENARIO 3 CRASHED: {e}")
        results['scenario_3'] = False

    try:
        results['scenario_4'] = test_scenario_4_typo_in_service_name()
    except Exception as e:
        print(f"\nSCENARIO 4 CRASHED: {e}")
        results['scenario_4'] = False

    try:
        results['scenario_5'] = test_scenario_5_all_services()
    except Exception as e:
        print(f"\nSCENARIO 5 CRASHED: {e}")
        results['scenario_5'] = False

    try:
        results['scenario_6'] = test_scenario_6_comma_separated()
    except Exception as e:
        print(f"\nSCENARIO 6 CRASHED: {e}")
        results['scenario_6'] = False

    # Generate final report
    print_header("FINAL REPORT")

    print("Test Results:")
    passed = sum(1 for v in results.values() if v)
    total = len(results)
    print(f"  Passed: {passed}/{total}")
    print()

    for scenario, result in results.items():
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"  {scenario}: {status}")

    print("\n" + "=" * 80)

    return all(results.values())


if __name__ == '__main__':
    success = main()
    sys.exit(0 if success else 1)
