"""
Visual flow test - shows exactly what the user sees during service selection.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


def visualize_user_flow():
    """Show the exact prompts and options a user sees."""
    print("\n" + "=" * 80)
    print("VISUAL USER FLOW: Service Selection")
    print("=" * 80 + "\n")

    runner = MockActionRunner()
    runner.input_queue = [
        'openmetadata kerberos',  # User's choice
        '', '', '', '', ''         # Postgres defaults
    ]

    print("Starting wizard...\n")
    engine = WizardEngine(runner=runner, base_path='wizard')
    engine.execute_flow('setup')

    print("\n" + "=" * 80)
    print("WHAT THE USER SEES:")
    print("=" * 80 + "\n")

    # Extract and display all user-facing messages
    step_num = 1
    for call in runner.calls:
        if call[0] == 'display':
            message = call[1]
            # Skip empty lines for clarity in this visualization
            if message.strip():
                print(f"{message}")

        elif call[0] == 'get_input':
            prompt = call[1]
            default = call[2] if len(call) > 2 else None

            # Show the prompt with default if present
            if default:
                print(f"\n{prompt} [{default}]: ", end="")
                print(f"<user pressed Enter>")
            else:
                print(f"\n{prompt}: ", end="")
                if step_num == 1:
                    print(f"openmetadata kerberos")
                else:
                    print(f"<user pressed Enter>")

            step_num += 1

    print("\n" + "=" * 80)
    print("RESULT:")
    print("=" * 80)
    print(f"\nServices enabled:")
    print(f"  - postgres: {engine.state.get('services.postgres.enabled')}")
    print(f"  - openmetadata: {engine.state.get('services.openmetadata.enabled')}")
    print(f"  - kerberos: {engine.state.get('services.kerberos.enabled')}")
    print(f"  - pagila: {engine.state.get('services.pagila.enabled')}")


def analyze_prompt_clarity():
    """Analyze the clarity of prompts for non-technical users."""
    print("\n" + "=" * 80)
    print("PROMPT CLARITY ANALYSIS")
    print("=" * 80 + "\n")

    runner = MockActionRunner()
    runner.input_queue = ['openmetadata', '', '', '', '', '']

    engine = WizardEngine(runner=runner, base_path='wizard')
    engine.execute_flow('setup')

    # Find the service selection prompt
    for call in runner.calls:
        if call[0] == 'get_input' and 'Select services' in call[1]:
            prompt = call[1]

            print("SERVICE SELECTION PROMPT:")
            print(f'  "{prompt}"')
            print()

            print("CLARITY ASSESSMENT:")
            print()

            # Check for key elements
            checks = [
                ("Tells user WHAT to do", "select services" in prompt.lower(), True),
                ("Tells user HOW to format", "space-separated" in prompt.lower(), True),
                ("Uses technical jargon", "multi_select" in prompt.lower() or "yaml" in prompt.lower(), False),
                ("Action-oriented verb", "select" in prompt.lower() or "choose" in prompt.lower(), True),
                ("Shows format example", "e.g." in prompt.lower() or "example" in prompt.lower(), False),
            ]

            for description, found, should_be_true in checks:
                if found == should_be_true:
                    status = "✓ GOOD"
                else:
                    status = "✗ ISSUE"

                print(f"  {status}: {description}")
                if found != should_be_true:
                    if should_be_true:
                        print(f"         Missing from prompt")
                    else:
                        print(f"         Should not be in user-facing prompt")

    print()

    # Check if options are displayed
    option_displays = [c for c in runner.calls if c[0] == 'display' and
                      ('openmetadata' in c[1].lower() or 'kerberos' in c[1].lower() or 'pagila' in c[1].lower())]

    print("\nOPTIONS DISPLAY:")
    if option_displays:
        print("  ✓ Options are shown to user before prompt")
        print("  Example:")
        for call in option_displays[:3]:
            print(f"    {call[1]}")
    else:
        print("  ✗ Options are NOT shown (user must guess names)")


def test_error_message_quality():
    """Test what happens with common user errors."""
    print("\n" + "=" * 80)
    print("ERROR HANDLING ANALYSIS")
    print("=" * 80 + "\n")

    test_cases = [
        ("Typo in service name", "openmedata"),
        ("Comma separation", "openmetadata,kerberos"),
        ("Extra spaces", "  openmetadata   kerberos  "),
        ("Mixed case", "OpenMetadata Kerberos"),
        ("Leading/trailing commas", "openmetadata, kerberos,"),
    ]

    for description, user_input in test_cases:
        print(f"\nTest: {description}")
        print(f"  User types: '{user_input}'")

        runner = MockActionRunner()
        runner.input_queue = [user_input, '', '', '', '', '']

        try:
            engine = WizardEngine(runner=runner, base_path='wizard')
            engine.execute_flow('setup')

            # Check what was stored
            selected = engine.state.get('selected_services', [])
            enabled_count = sum([
                engine.state.get('services.openmetadata.enabled', False),
                engine.state.get('services.kerberos.enabled', False),
                engine.state.get('services.pagila.enabled', False)
            ])

            print(f"  Stored as: {selected}")
            print(f"  Services enabled: {enabled_count}")

            # Check if any error messages were shown
            error_messages = [c for c in runner.calls if c[0] == 'display' and
                            ('error' in c[1].lower() or 'invalid' in c[1].lower() or 'unknown' in c[1].lower())]

            if error_messages:
                print(f"  ✓ Error message shown: {error_messages[0][1]}")
            else:
                print(f"  ✗ No error message (silent failure)")

        except Exception as e:
            print(f"  ✗ CRASHED: {e}")


if __name__ == '__main__':
    visualize_user_flow()
    analyze_prompt_clarity()
    test_error_message_quality()
