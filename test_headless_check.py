#!/usr/bin/env python3
"""Check if headless mode is working correctly."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


def test_headless_mode():
    """Test if headless mode is set properly."""
    runner = MockActionRunner()
    runner.input_queue = ['postgres:16', 'y', 'trust', '5433']

    engine = WizardEngine(runner=runner, base_path='wizard')

    # Mock docker
    runner.responses['check_docker'] = True
    runner.responses['file_exists'] = {'platform-config.yaml': False}

    print("Before execute_flow:")
    print(f"  headless_mode: {getattr(engine, 'headless_mode', 'NOT SET')}")
    print(f"  headless_inputs: {getattr(engine, 'headless_inputs', 'NOT SET')}")

    # Execute with NO headless_inputs parameter
    engine.execute_flow('setup')

    print("\nAfter execute_flow:")
    print(f"  headless_mode: {engine.headless_mode}")
    print(f"  headless_inputs: {engine.headless_inputs}")

    print("\nInput queue status:")
    print(f"  Remaining items: {runner.input_queue}")
    print(f"  Used: {4 - len(runner.input_queue)} items")


if __name__ == '__main__':
    test_headless_mode()
