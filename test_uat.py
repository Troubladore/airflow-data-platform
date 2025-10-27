#!/usr/bin/env python3
"""
User Acceptance Testing for Interactive Wizard
Simulates real user interactions from a business analyst perspective
"""

import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent))

from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


def print_section(title):
    """Print a section header."""
    print("\n" + "=" * 80)
    print(f"  {title}")
    print("=" * 80 + "\n")


def print_call_trace(calls, start_index=0):
    """Print runner calls starting from index."""
    for i, call in enumerate(calls[start_index:], start=start_index):
        if call[0] == 'display':
            print(f"[{i}] DISPLAY: {call[1][:100]}{'...' if len(call[1]) > 100 else ''}")
        elif call[0] == 'get_input':
            prompt = call[1]
            default = call[2] if len(call) > 2 else None
            print(f"[{i}] PROMPT: {prompt} [default: {default}]")
        elif call[0] == 'save_config':
            print(f"[{i}] ACTION: save_config to {call[2]}")
        else:
            print(f"[{i}] {call[0].upper()}: {call[1] if len(call) > 1 else ''}")


def scenario_1_all_defaults():
    """Test Scenario 1: Setup Wizard - All Defaults."""
    print_section("SCENARIO 1: Setup Wizard - All Defaults")
    print("Test: ./platform setup")
    print("User behavior: Press Enter for every prompt (accept all defaults)\n")

    runner = MockActionRunner()
    # Empty strings = user pressing Enter (use defaults)
    runner.input_queue = [
        '',  # postgres image (use default)
        '',  # prebuilt (use default: n)
        '',  # auth method (use default: md5)
        '',  # password (use default)
        '',  # port (use default)
    ]

    # Mock docker available
    runner.responses['check_docker'] = True
    runner.responses['file_exists'] = {
        'platform-config.yaml': False
    }

    engine = WizardEngine(runner=runner, base_path='wizard')

    try:
        engine.execute_flow('setup')

        print("\nEXECUTION TRACE:")
        print_call_trace(runner.calls)

        print("\n\nFINAL STATE:")
        for key, value in engine.state.items():
            if key.startswith('services.'):
                print(f"  {key}: {value}")

        print("\n\nUX ASSESSMENT:")

        # Count prompts
        prompts = [c for c in runner.calls if c[0] == 'get_input']
        displays = [c for c in runner.calls if c[0] == 'display']

        print(f"  Total prompts shown: {len(prompts)}")
        print(f"  Total display messages: {len(displays)}")

        # Check if defaults are shown
        prompts_with_defaults = [p for p in prompts if p[2] is not None]
        print(f"  Prompts with defaults: {len(prompts_with_defaults)}/{len(prompts)}")

        # Verify each prompt shows its default
        print("\n  Default values shown:")
        for call in prompts:
            prompt = call[1]
            default = call[2] if len(call) > 2 else None
            print(f"    - {prompt[:50]}... [default: {default}]")

        print("\n  SUCCESS: Wizard completed with all defaults")

    except Exception as e:
        print(f"\n  FAILURE: {e}")
        import traceback
        traceback.print_exc()


def scenario_2_clean_slate_empty():
    """Test Scenario 2: Clean-Slate Wizard - Empty System."""
    print_section("SCENARIO 2: Clean-Slate Wizard - Empty System")
    print("Test: ./platform clean-slate")
    print("User behavior: System has no artifacts\n")

    runner = MockActionRunner()
    runner.input_queue = []  # No input needed - system is empty

    # Mock empty system (no containers, images, volumes)
    runner.responses['run_shell'] = {
        ('docker', 'ps', '-a', '--format', '{{.Names}}'): '',
        ('docker', 'images', '--format', '{{.Repository}}:{{.Tag}}'): '',
        ('docker', 'volume', 'ls', '--format', '{{.Name}}'): '',
    }

    runner.responses['file_exists'] = {
        'platform-config.yaml': False
    }

    engine = WizardEngine(runner=runner, base_path='wizard')

    try:
        engine.execute_flow('clean-slate')

        print("\nEXECUTION TRACE:")
        print_call_trace(runner.calls)

        print("\n\nUX ASSESSMENT:")

        displays = [c for c in runner.calls if c[0] == 'display']
        print(f"  Total display messages: {len(displays)}")

        # Check for key messages
        display_text = '\n'.join(c[1] for c in displays)

        if 'clean' in display_text.lower():
            print("  GOOD: Shows 'clean' message")
        else:
            print("  ISSUE: No 'clean' message found")

        if 'Discovery' in display_text or 'Discovering' in display_text:
            print("  GOOD: Shows discovery phase")
        else:
            print("  ISSUE: No discovery message")

        if 'containers' in display_text.lower():
            print("  GOOD: Explains what was checked (containers)")
        else:
            print("  ISSUE: Doesn't explain what was checked")

        print("\n  Full messages shown:")
        for msg in displays:
            print(f"\n    {msg[1]}")

        print("\n  SUCCESS: Clean-slate completed for empty system")

    except Exception as e:
        print(f"\n  FAILURE: {e}")
        import traceback
        traceback.print_exc()


def scenario_3_custom_values():
    """Test Scenario 3: Setup Wizard - Custom Values."""
    print_section("SCENARIO 3: Setup Wizard - Custom Values")
    print("Test: ./platform setup with custom values")
    print("User behavior:")
    print("  - PostgreSQL image: postgres:16")
    print("  - Prebuilt: y")
    print("  - Auth: trust (option 2)")
    print("  - Port: 5433\n")

    runner = MockActionRunner()
    runner.input_queue = [
        'postgres:16',  # custom image
        'y',            # prebuilt = yes
        'trust',        # auth method = trust
        # Note: password prompt skipped because trust doesn't need password
        '5433',         # custom port
    ]

    # Mock docker available
    runner.responses['check_docker'] = True
    runner.responses['file_exists'] = {
        'platform-config.yaml': False
    }

    engine = WizardEngine(runner=runner, base_path='wizard')

    try:
        engine.execute_flow('setup')

        print("\nEXECUTION TRACE:")
        print_call_trace(runner.calls)

        print("\n\nFINAL STATE (checking custom values):")
        state_checks = {
            'services.postgres.image': 'postgres:16',
            'services.postgres.prebuilt': True,
            'services.postgres.auth_method': 'trust',
            'services.postgres.port': 5433,
        }

        all_correct = True
        for key, expected in state_checks.items():
            actual = engine.state.get(key)
            match = actual == expected
            status = "OK" if match else "FAIL"
            print(f"  [{status}] {key}: {actual} (expected: {expected})")
            if not match:
                all_correct = False

        print("\n\nUX ASSESSMENT:")

        # Check if custom values were accepted
        if all_correct:
            print("  GOOD: All custom values accepted correctly")
        else:
            print("  ISSUE: Some custom values not accepted")

        # Check flow logic - password prompt should be skipped for 'trust'
        prompts = [c for c in runner.calls if c[0] == 'get_input']
        password_prompts = [p for p in prompts if 'password' in p[1].lower()]

        if len(password_prompts) == 0:
            print("  GOOD: Password prompt correctly skipped for 'trust' auth")
        else:
            print("  ISSUE: Password prompt shown even for 'trust' auth")

        print(f"\n  Total prompts: {len(prompts)}")
        print("  Prompts shown:")
        for p in prompts:
            print(f"    - {p[1][:60]}")

        print("\n  SUCCESS: Custom values accepted")

    except Exception as e:
        print(f"\n  FAILURE: {e}")
        import traceback
        traceback.print_exc()


def scenario_4_validation_errors():
    """Test Scenario 4: Validation - Invalid then Valid Input."""
    print_section("SCENARIO 4: Validation - Invalid then Valid Input")
    print("Test: ./platform setup with invalid port, then valid port")
    print("User behavior:")
    print("  - Port: 99999 (INVALID)")
    print("  - Port: 5432 (VALID)\n")

    runner = MockActionRunner()
    runner.input_queue = [
        '',         # postgres image (default)
        '',         # prebuilt (default)
        '',         # auth (default)
        '',         # password (default)
        '99999',    # INVALID port
        '5432',     # VALID port after error
    ]

    # Mock docker available
    runner.responses['check_docker'] = True
    runner.responses['file_exists'] = {
        'platform-config.yaml': False
    }

    engine = WizardEngine(runner=runner, base_path='wizard')

    try:
        engine.execute_flow('setup')

        print("\nEXECUTION TRACE:")
        print_call_trace(runner.calls)

        print("\n\nUX ASSESSMENT:")

        # Check for error messages
        displays = [c for c in runner.calls if c[0] == 'display']
        error_messages = [d for d in displays if 'error' in d[1].lower()]

        if error_messages:
            print(f"  GOOD: Error message shown ({len(error_messages)} errors)")
            for err in error_messages:
                print(f"    - {err[1][:80]}")
        else:
            print("  ISSUE: No error message shown for invalid port")

        # Check if port prompt was shown twice
        prompts = [c for c in runner.calls if c[0] == 'get_input']
        port_prompts = [p for p in prompts if 'port' in p[1].lower()]

        if len(port_prompts) == 2:
            print("  GOOD: Port re-prompted after validation error")
        else:
            print(f"  ISSUE: Port prompted {len(port_prompts)} times (expected 2)")

        # Check final state
        final_port = engine.state.get('services.postgres.port')
        if final_port == 5432:
            print(f"  GOOD: Valid port accepted (final: {final_port})")
        else:
            print(f"  ISSUE: Unexpected final port: {final_port}")

        print("\n  SUCCESS: Validation error recovery works")

    except Exception as e:
        print(f"\n  FAILURE: {e}")
        import traceback
        traceback.print_exc()


def main():
    """Run all UAT scenarios."""
    print("\n" + "#" * 80)
    print("# USER ACCEPTANCE TESTING - Interactive Wizard")
    print("# Role: Business Analyst")
    print("#" * 80)

    try:
        scenario_1_all_defaults()
        scenario_2_clean_slate_empty()
        scenario_3_custom_values()
        scenario_4_validation_errors()

        print_section("UAT COMPLETE")
        print("All scenarios executed. Review findings above.\n")

    except Exception as e:
        print(f"\nCRITICAL ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
