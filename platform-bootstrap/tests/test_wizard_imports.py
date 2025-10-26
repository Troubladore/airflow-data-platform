#!/usr/bin/env python3
"""
Test wizard module imports - RED phase of TDD.

These tests verify that the wizard module structure exists and
can be imported correctly. They should fail initially (RED),
then pass after creating the module structure (GREEN).
"""

import unittest
import sys
from pathlib import Path

# Add parent directory to path to import wizard module
sys.path.insert(0, str(Path(__file__).parent.parent))


class TestWizardImports(unittest.TestCase):
    """Test that wizard module and its components can be imported."""

    def test_import_wizard_module(self):
        """Test that the wizard module can be imported."""
        try:
            import wizard
            self.assertIsNotNone(wizard)
        except ImportError as e:
            self.fail(f"Failed to import wizard module: {e}")

    def test_import_wizard_engine_from_init(self):
        """Test that WizardEngine can be imported from wizard package."""
        try:
            from wizard import WizardEngine
            self.assertIsNotNone(WizardEngine)
        except ImportError as e:
            self.fail(f"Failed to import WizardEngine from wizard: {e}")

    def test_import_action_runner_from_init(self):
        """Test that ActionRunner can be imported from wizard package."""
        try:
            from wizard import ActionRunner
            self.assertIsNotNone(ActionRunner)
        except ImportError as e:
            self.fail(f"Failed to import ActionRunner from wizard: {e}")

    def test_import_real_action_runner_from_init(self):
        """Test that RealActionRunner can be imported from wizard package."""
        try:
            from wizard import RealActionRunner
            self.assertIsNotNone(RealActionRunner)
        except ImportError as e:
            self.fail(f"Failed to import RealActionRunner from wizard: {e}")

    def test_import_mock_action_runner_from_init(self):
        """Test that MockActionRunner can be imported from wizard package."""
        try:
            from wizard import MockActionRunner
            self.assertIsNotNone(MockActionRunner)
        except ImportError as e:
            self.fail(f"Failed to import MockActionRunner from wizard: {e}")

    def test_wizard_engine_module_exists(self):
        """Test that wizard_engine module exists."""
        try:
            from wizard import wizard_engine
            self.assertIsNotNone(wizard_engine)
        except ImportError as e:
            self.fail(f"Failed to import wizard_engine module: {e}")

    def test_wizard_validators_module_exists(self):
        """Test that wizard_validators module exists."""
        try:
            from wizard import wizard_validators
            self.assertIsNotNone(wizard_validators)
        except ImportError as e:
            self.fail(f"Failed to import wizard_validators module: {e}")

    def test_wizard_actions_module_exists(self):
        """Test that wizard_actions module exists."""
        try:
            from wizard import wizard_actions
            self.assertIsNotNone(wizard_actions)
        except ImportError as e:
            self.fail(f"Failed to import wizard_actions module: {e}")

    def test_action_runner_module_exists(self):
        """Test that action_runner module exists."""
        try:
            from wizard import action_runner
            self.assertIsNotNone(action_runner)
        except ImportError as e:
            self.fail(f"Failed to import action_runner module: {e}")


if __name__ == '__main__':
    unittest.main()
