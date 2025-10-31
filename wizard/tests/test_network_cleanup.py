"""Test network cleanup in clean-slate process."""

import pytest
from unittest.mock import Mock, patch, call
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import ActionRunner
from wizard.engine.schema import Step


class TestNetworkCleanup:
    """Test that clean-slate properly removes the platform_network."""

    def test_cleanup_orphaned_resources_removes_platform_network(self):
        """Test that cleanup_orphaned_resources action removes platform_network."""
        # Arrange
        mock_runner = Mock(spec=ActionRunner)
        mock_runner.run_shell = Mock(return_value={'returncode': 0, 'stdout': '', 'stderr': ''})

        # Create engine with mock runner
        engine = WizardEngine(runner=mock_runner)
        engine.actions = {}  # Set empty actions dict

        # Create a cleanup step
        cleanup_step = Step(
            id='cleanup_orphaned_resources',
            type='action',
            action='discovery.cleanup_orphaned_resources',
            next=None
        )

        # Act
        engine._execute_step(cleanup_step)

        # Assert - verify network removal was called
        actual_calls = mock_runner.run_shell.call_args_list

        # Filter for docker commands only (ignore config file reads)
        docker_calls = [call_args for call_args in actual_calls
                       if 'docker' in str(call_args[0][0])]

        # Verify network removal was called
        network_rm_called = any(
            'network' in str(call_args) and 'rm' in str(call_args) and 'platform_network' in str(call_args)
            for call_args in docker_calls
        )
        assert network_rm_called, f"Docker network rm platform_network was not called. Docker calls were: {docker_calls}"

    def test_network_removal_ignores_errors(self):
        """Test that network removal continues even if network doesn't exist."""
        # Arrange
        mock_runner = Mock(spec=ActionRunner)

        # Simulate network not existing (error from docker)
        # Since run_shell doesn't return error codes in the mock runner,
        # we'll simulate an exception being raised
        def side_effect(cmd, **kwargs):
            if 'network' in cmd and 'rm' in cmd:
                raise Exception("Error: network 'platform_network' not found")
            return {'returncode': 0, 'stdout': '', 'stderr': ''}

        mock_runner.run_shell = Mock(side_effect=side_effect)

        # Create engine with mock runner
        engine = WizardEngine(runner=mock_runner)
        engine.actions = {}  # Set empty actions dict

        # Create a cleanup step
        cleanup_step = Step(
            id='cleanup_orphaned_resources',
            type='action',
            action='discovery.cleanup_orphaned_resources',
            next=None
        )

        # Act - should not raise an exception even though network removal fails
        result = engine._execute_step(cleanup_step)

        # Assert - execution completed without error
        assert result is None  # Step returns None on success

        # Verify network removal was attempted
        network_rm_calls = [
            call_args for call_args in mock_runner.run_shell.call_args_list
            if 'network' in str(call_args) and 'rm' in str(call_args)
        ]

        assert len(network_rm_calls) > 0, "Network removal was not attempted"