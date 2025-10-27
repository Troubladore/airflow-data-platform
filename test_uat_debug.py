#!/usr/bin/env python3
"""
Debug UAT - Trace step execution in detail
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


def debug_scenario_1():
    """Debug Scenario 1 with detailed tracing."""
    print("=" * 80)
    print("DEBUG: Setup Wizard - All Defaults")
    print("=" * 80)

    runner = MockActionRunner()
    runner.input_queue = [
        '',  # postgres image (use default)
        '',  # prebuilt (use default: n)
        '',  # auth method (use default: md5)
        '',  # password (use default)
        '',  # port (use default)
    ]

    runner.responses['check_docker'] = True
    runner.responses['file_exists'] = {'platform-config.yaml': False}

    engine = WizardEngine(runner=runner, base_path='wizard')

    # Patch _execute_service to trace step navigation
    original_execute_service = engine._execute_service

    def traced_execute_service(service_spec, headless_inputs=None):
        print(f"\n>>> Executing service: {service_spec.service}")
        print(f"    Total steps: {len(service_spec.steps)}")

        if not service_spec.steps:
            print("    No steps to execute")
            return

        # Start with first step
        current_step_id = service_spec.steps[0].id
        step_count = 0

        while current_step_id:
            step = engine._get_step_by_id(service_spec, current_step_id)
            if not step:
                print(f"    [{step_count}] STOP: Step '{current_step_id}' not found")
                break

            step_count += 1
            print(f"\n    [{step_count}] Step: {step.id} (type: {step.type})")

            # Track old value for conditional next
            old_value = engine.state.get(step.state_key) if step.state_key else None
            print(f"        Old value: {old_value}")

            # Execute step
            new_value = engine._execute_step(step, headless_inputs)
            print(f"        New value: {new_value}")

            # Store in state
            if step.state_key:
                print(f"        State[{step.state_key}] = {new_value}")

            # Resolve next step
            next_step_id = engine._resolve_next(step, new_value, old_value)
            print(f"        Next config: {step.next}")
            print(f"        Next resolved: {next_step_id}")

            # If no explicit next, go to next step in sequence
            if next_step_id is None and step.next is None:
                current_index = next(
                    (i for i, s in enumerate(service_spec.steps) if s.id == current_step_id),
                    None
                )
                if current_index is not None and current_index + 1 < len(service_spec.steps):
                    next_step_id = service_spec.steps[current_index + 1].id
                    print(f"        Sequential next: {next_step_id}")
                else:
                    print(f"        Sequential next: None (end of steps)")

            current_step_id = next_step_id

        print(f"\n    Execution complete. Total steps executed: {step_count}")

    engine._execute_service = traced_execute_service

    try:
        engine.execute_flow('setup')
        print("\n" + "=" * 80)
        print("FINAL STATE:")
        print("=" * 80)
        for key in sorted(engine.state.keys()):
            if key.startswith('services.'):
                print(f"  {key}: {engine.state[key]}")

    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    debug_scenario_1()
