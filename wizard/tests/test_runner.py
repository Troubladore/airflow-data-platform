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


class TestGetInputMethod:
    """Test get_input() method in ActionRunner implementations."""

    def test_real_runner_has_get_input_method(self):
        """RealActionRunner should have get_input() method."""
        runner = RealActionRunner()
        assert hasattr(runner, 'get_input')
        assert callable(runner.get_input)

    def test_mock_runner_has_get_input_method(self):
        """MockActionRunner should have get_input() method."""
        runner = MockActionRunner()
        assert hasattr(runner, 'get_input')
        assert callable(runner.get_input)

    def test_mock_runner_captures_get_input_calls(self):
        """MockActionRunner should record get_input() calls."""
        runner = MockActionRunner()

        result = runner.get_input("Enter name:", "default")

        assert len(runner.calls) == 1
        assert runner.calls[0] == ('get_input', 'Enter name:', 'default')

    def test_mock_runner_returns_from_input_queue(self):
        """MockActionRunner should return values from input_queue."""
        runner = MockActionRunner()
        runner.input_queue = ['value1', 'value2']

        result1 = runner.get_input("Prompt 1:", None)
        result2 = runner.get_input("Prompt 2:", None)

        assert result1 == 'value1'
        assert result2 == 'value2'

    def test_mock_runner_returns_default_when_queue_empty(self):
        """MockActionRunner should return default if input_queue empty."""
        runner = MockActionRunner()
        runner.input_queue = []

        result = runner.get_input("Prompt:", "default_value")

        assert result == 'default_value'
