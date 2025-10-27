#!/usr/bin/env python3
"""
Test runner parity - verify Mock and Real runners behave the same
"""

import sys
from pathlib import Path
from io import StringIO

sys.path.insert(0, str(Path(__file__).parent))

from wizard.engine.runner import MockActionRunner, RealActionRunner


def test_real_runner_applies_defaults():
    """Test that RealActionRunner applies defaults for empty input."""
    print("=" * 80)
    print("Test: RealActionRunner applies defaults for empty input")
    print("=" * 80)

    # Simulate user pressing Enter (empty input)
    import sys
    old_stdin = sys.stdin
    sys.stdin = StringIO('\n')  # Empty line = user pressed Enter

    runner = RealActionRunner()
    result = runner.get_input("Test prompt", default="default_value")

    sys.stdin = old_stdin

    print(f"Input: <Enter>")
    print(f"Default: 'default_value'")
    print(f"Result: '{result}'")

    if result == "default_value":
        print("✅ PASS: RealActionRunner applies default for empty input")
        return True
    else:
        print(f"❌ FAIL: Expected 'default_value', got '{result}'")
        return False


def test_mock_runner_current_behavior():
    """Test current MockActionRunner behavior (buggy)."""
    print("\n" + "=" * 80)
    print("Test: MockActionRunner CURRENT behavior (buggy)")
    print("=" * 80)

    runner = MockActionRunner()
    runner.input_queue = ['']  # Empty string in queue

    result = runner.get_input("Test prompt", default="default_value")

    print(f"Queue: ['']")
    print(f"Default: 'default_value'")
    print(f"Result: '{result}'")

    if result == '':
        print("❌ CURRENT: MockActionRunner returns empty string (doesn't apply default)")
        print("   This is the BUG - doesn't match RealActionRunner behavior!")
        return False
    else:
        print(f"Result: '{result}'")
        return True


def test_mock_runner_fixed_behavior():
    """Test what MockActionRunner SHOULD do (fixed)."""
    print("\n" + "=" * 80)
    print("Test: MockActionRunner FIXED behavior")
    print("=" * 80)

    # Monkey-patch the fix
    original_get_input = MockActionRunner.get_input

    def fixed_get_input(self, prompt: str, default: str = None) -> str:
        """Fixed version that matches RealActionRunner."""
        self.calls.append(('get_input', prompt, default))

        if self.input_queue:
            response = self.input_queue.pop(0)
            # Match RealActionRunner: apply default if response is empty
            return response if response else (default if default else '')

        return default if default else ''

    MockActionRunner.get_input = fixed_get_input

    runner = MockActionRunner()
    runner.input_queue = ['']  # Empty string in queue

    result = runner.get_input("Test prompt", default="default_value")

    # Restore original
    MockActionRunner.get_input = original_get_input

    print(f"Queue: ['']")
    print(f"Default: 'default_value'")
    print(f"Result: '{result}'")

    if result == "default_value":
        print("✅ FIXED: MockActionRunner now applies default (matches RealActionRunner)")
        return True
    else:
        print(f"❌ FAIL: Expected 'default_value', got '{result}'")
        return False


def test_parity():
    """Test that both runners return same result for same input."""
    print("\n" + "=" * 80)
    print("Test: Mock/Real parity check")
    print("=" * 80)

    # Test cases
    test_cases = [
        ("", "default1", "Empty input with default"),
        ("explicit", "default2", "Explicit input with default"),
        ("", None, "Empty input without default"),
    ]

    results = []

    for input_val, default, description in test_cases:
        print(f"\n  Test case: {description}")
        print(f"    Input: '{input_val}'")
        print(f"    Default: {default}")

        # Real runner
        import sys
        from io import StringIO
        old_stdin = sys.stdin
        sys.stdin = StringIO(input_val + '\n')
        real_runner = RealActionRunner()
        real_result = real_runner.get_input("Test", default=default)
        sys.stdin = old_stdin

        # Mock runner (current buggy version)
        mock_runner = MockActionRunner()
        mock_runner.input_queue = [input_val]
        mock_result = mock_runner.get_input("Test", default=default)

        print(f"    Real result: '{real_result}'")
        print(f"    Mock result: '{mock_result}'")

        if real_result == mock_result:
            print(f"    ✅ MATCH")
            results.append(True)
        else:
            print(f"    ❌ MISMATCH - This is the bug!")
            results.append(False)

    all_pass = all(results)
    print(f"\n  Overall: {'✅ PASS' if all_pass else '❌ FAIL'} - {sum(results)}/{len(results)} cases match")
    return all_pass


def main():
    """Run all parity tests."""
    print("\n" + "#" * 80)
    print("# Runner Parity Tests - Mock vs Real ActionRunner")
    print("#" * 80)

    results = []

    results.append(test_real_runner_applies_defaults())
    results.append(not test_mock_runner_current_behavior())  # Invert because we expect it to fail
    results.append(test_mock_runner_fixed_behavior())
    results.append(test_parity())

    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)

    print(f"✅ RealActionRunner: Works correctly")
    print(f"❌ MockActionRunner: Currently broken (doesn't match Real)")
    print(f"✅ Fix available: Apply default for empty input")

    print("\n" + "=" * 80)
    print("RECOMMENDATION")
    print("=" * 80)
    print("Fix MockActionRunner.get_input() to match RealActionRunner behavior:")
    print("")
    print("  def get_input(self, prompt: str, default: str = None) -> str:")
    print("      self.calls.append(('get_input', prompt, default))")
    print("      if self.input_queue:")
    print("          response = self.input_queue.pop(0)")
    print("          # Match RealActionRunner: apply default if response is empty")
    print("          return response if response else (default if default else '')")
    print("      return default if default else ''")


if __name__ == '__main__':
    main()
