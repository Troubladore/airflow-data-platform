"""Tests for ActionRunner interface and implementations."""

import pytest
from wizard.engine.runner import ActionRunner, RealActionRunner, MockActionRunner


def test_action_runner_is_abstract():
    """ActionRunner cannot be instantiated directly."""
    with pytest.raises(TypeError):
        ActionRunner()


def test_mock_runner_records_save_config():
    """MockActionRunner records save_config calls."""
    mock = MockActionRunner()
    config = {'services': {'postgres': {'enabled': True}}}

    mock.save_config(config, 'platform-config.yaml')

    assert len(mock.calls) == 1
    assert mock.calls[0][0] == 'save_config'
    assert mock.calls[0][1] == config
    assert mock.calls[0][2] == 'platform-config.yaml'


def test_mock_runner_records_run_shell():
    """MockActionRunner records run_shell calls."""
    mock = MockActionRunner()
    command = ['make', '-C', 'platform-infrastructure', 'start']

    result = mock.run_shell(command, cwd='/tmp')

    assert len(mock.calls) == 1
    assert mock.calls[0][0] == 'run_shell'
    assert mock.calls[0][1] == command
    assert mock.calls[0][2] == '/tmp'
    # Default response
    assert result['returncode'] == 0
    assert result['stdout'] == ''


def test_mock_runner_records_check_docker():
    """MockActionRunner records check_docker calls."""
    mock = MockActionRunner()

    result = mock.check_docker()

    assert len(mock.calls) == 1
    assert mock.calls[0][0] == 'check_docker'
    assert result is True  # Default response


def test_mock_runner_custom_responses():
    """MockActionRunner can return custom responses."""
    mock = MockActionRunner()
    mock.responses['run_shell'] = {
        'stdout': 'success',
        'stderr': 'warning',
        'returncode': 0
    }
    mock.responses['check_docker'] = False

    shell_result = mock.run_shell(['ls'])
    docker_result = mock.check_docker()

    assert shell_result['stdout'] == 'success'
    assert shell_result['stderr'] == 'warning'
    assert docker_result is False


def test_real_runner_has_required_methods():
    """RealActionRunner implements all required methods."""
    runner = RealActionRunner()

    # Check methods exist (not calling them to avoid side effects in test)
    assert hasattr(runner, 'save_config')
    assert hasattr(runner, 'run_shell')
    assert hasattr(runner, 'check_docker')
    assert callable(runner.save_config)
    assert callable(runner.run_shell)
    assert callable(runner.check_docker)
