"""Tests for ActionRunner interface in wizard engine."""

import pytest
from wizard.engine.runner import ActionRunner, RealActionRunner, MockActionRunner


class TestDisplayMethod:
    """Test display() method in ActionRunner implementations."""

    def test_real_runner_has_display_method(self):
        """RealActionRunner should have display() method."""
        runner = RealActionRunner()
        assert hasattr(runner, 'display')
        assert callable(runner.display)

    def test_mock_runner_has_display_method(self):
        """MockActionRunner should have display() method."""
        runner = MockActionRunner()
        assert hasattr(runner, 'display')
        assert callable(runner.display)

    def test_mock_runner_captures_display_calls(self):
        """MockActionRunner should record display() calls."""
        runner = MockActionRunner()

        runner.display("Test message")

        assert len(runner.calls) == 1
        assert runner.calls[0] == ('display', 'Test message')

    def test_mock_runner_captures_multiple_displays(self):
        """MockActionRunner should record multiple display calls."""
        runner = MockActionRunner()

        runner.display("Message 1")
        runner.display("Message 2")

        assert len(runner.calls) == 2
        assert runner.calls[0] == ('display', 'Message 1')
        assert runner.calls[1] == ('display', 'Message 2')
