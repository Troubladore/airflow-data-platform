"""Tests for Pagila teardown - RED phase"""
import pytest
import yaml
from pathlib import Path
from wizard.engine.runner import MockActionRunner


# ============================================================================
# TEARDOWN SPEC TESTS
# ============================================================================

def test_teardown_spec_file_exists():
    """teardown-spec.yaml file should exist in pagila service directory"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"
    assert spec_path.exists(), "teardown-spec.yaml file not found"


def test_teardown_spec_loads_as_valid_yaml():
    """teardown-spec.yaml should be valid YAML that can be loaded"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert spec is not None
    assert isinstance(spec, dict)


def test_teardown_spec_has_service_name():
    """teardown-spec.yaml should declare service name as 'pagila'"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert 'service' in spec
    assert spec['service'] == 'pagila'


def test_teardown_spec_has_version():
    """teardown-spec.yaml should declare a version"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert 'version' in spec
    assert isinstance(spec['version'], (str, float))


def test_teardown_spec_has_description():
    """teardown-spec.yaml should have a description"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert 'description' in spec
    assert len(spec['description']) > 0


def test_teardown_spec_has_steps():
    """teardown-spec.yaml should define teardown steps"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert 'steps' in spec
    assert isinstance(spec['steps'], list)
    assert len(spec['steps']) > 0


def test_teardown_spec_has_confirmation_step():
    """teardown-spec.yaml should have a confirmation step"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Should have a confirmation step (typically yes/no)
    confirm_steps = [s for s in steps if 'confirm' in s.get('id', '').lower()]
    assert len(confirm_steps) > 0, "No confirmation step found"


def test_teardown_spec_has_drop_database_action():
    """teardown-spec.yaml should have an action to drop the database"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Should have action step for dropping database
    action_steps = [s for s in steps if s.get('type') == 'action']
    drop_steps = [s for s in action_steps if 'drop' in s.get('action', '').lower()]
    assert len(drop_steps) > 0, "No database drop action found"


def test_teardown_spec_has_remove_repo_action():
    """teardown-spec.yaml should have an action to remove repository"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Should have action step for removing repo
    action_steps = [s for s in steps if s.get('type') == 'action']
    remove_steps = [s for s in action_steps if 'remove' in s.get('action', '').lower() or 'repo' in s.get('action', '').lower()]
    assert len(remove_steps) > 0, "No repository removal action found"


def test_teardown_spec_has_clean_config_action():
    """teardown-spec.yaml should have an action to clean configuration"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Should have action step for cleaning config
    action_steps = [s for s in steps if s.get('type') == 'action']
    clean_steps = [s for s in action_steps if 'clean' in s.get('action', '').lower() or 'config' in s.get('action', '').lower()]
    assert len(clean_steps) > 0, "No config cleanup action found"


def test_teardown_spec_step_ids_are_namespaced():
    """Boolean prompt step IDs should be namespaced with 'pagila_' prefix for flow integration"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Check that boolean prompt steps are namespaced
    boolean_steps = [s for s in steps if s.get('type') == 'boolean']

    for step in boolean_steps:
        step_id = step.get('id', '')
        assert step_id.startswith('pagila_'), \
            f"Boolean step ID '{step_id}' should be namespaced with 'pagila_' prefix"

    # Verify we have the expected namespaced boolean steps
    boolean_step_ids = [s.get('id') for s in boolean_steps]
    assert 'pagila_teardown_confirm' in boolean_step_ids
    assert 'pagila_remove_images_question' in boolean_step_ids
    assert 'pagila_remove_repo_question' in boolean_step_ids
    assert 'pagila_remove_database_data_question' in boolean_step_ids
    assert 'pagila_remove_config_question' in boolean_step_ids


def test_teardown_spec_actions_are_namespaced():
    """All action references should be namespaced with 'pagila.' prefix"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    for step in steps:
        if 'action' in step:
            action = step['action']
            assert action.startswith('pagila.'), \
                f"Action '{action}' not namespaced with 'pagila.'"


# ============================================================================
# TEARDOWN ACTIONS TESTS
# ============================================================================

def test_drop_database_action_exists():
    """drop_database action should be importable"""
    from wizard.services.pagila.teardown_actions import drop_database
    assert callable(drop_database)


def test_drop_database_calls_psql():
    """drop_database should execute dropdb command via docker exec"""
    from wizard.services.pagila.teardown_actions import drop_database

    mock_runner = MockActionRunner()
    ctx = {}

    drop_database(ctx, mock_runner)

    # Assert runner.run_shell was called
    assert len(mock_runner.calls) == 1
    assert mock_runner.calls[0][0] == 'run_shell'

    # Assert command uses docker exec and dropdb
    command = mock_runner.calls[0][1]
    command_str = ' '.join(command)
    assert 'docker' in command_str.lower()
    assert 'exec' in command_str.lower()
    assert 'dropdb' in command_str.lower()


def test_drop_database_targets_pagila_db():
    """drop_database should target the pagila database specifically"""
    from wizard.services.pagila.teardown_actions import drop_database

    mock_runner = MockActionRunner()
    ctx = {}

    drop_database(ctx, mock_runner)

    command = mock_runner.calls[0][1]
    command_str = ' '.join(command)
    assert 'pagila' in command_str.lower()


def test_drop_database_uses_if_exists():
    """drop_database should handle errors gracefully with || true"""
    from wizard.services.pagila.teardown_actions import drop_database

    mock_runner = MockActionRunner()
    ctx = {}

    drop_database(ctx, mock_runner)

    command = mock_runner.calls[0][1]
    command_str = ' '.join(command)
    # Verify it uses error suppression (|| true) for safe operation
    assert '||' in command_str or 'true' in command_str.lower()


def test_remove_repo_action_exists():
    """remove_repo action should be importable"""
    from wizard.services.pagila.teardown_actions import remove_repo
    assert callable(remove_repo)


def test_remove_repo_deletes_directory():
    """remove_repo should delete the repository directory"""
    from wizard.services.pagila.teardown_actions import remove_repo

    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_path': '/tmp/pagila'
    }

    remove_repo(ctx, mock_runner)

    # Assert runner.run_shell was called
    assert len(mock_runner.calls) == 1
    assert mock_runner.calls[0][0] == 'run_shell'

    # Assert command removes directory
    command = mock_runner.calls[0][1]
    command_str = ' '.join(command)
    assert 'rm' in command_str
    assert '/tmp/pagila' in command_str


def test_remove_repo_uses_recursive_force():
    """remove_repo should use rm -rf for complete removal"""
    from wizard.services.pagila.teardown_actions import remove_repo

    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_path': '/tmp/pagila'
    }

    remove_repo(ctx, mock_runner)

    command = mock_runner.calls[0][1]
    command_str = ' '.join(command)
    assert '-rf' in command_str or ('-r' in command_str and '-f' in command_str)


def test_remove_repo_handles_missing_path():
    """remove_repo should discover path when not in context"""
    from wizard.services.pagila.teardown_actions import remove_repo

    mock_runner = MockActionRunner()
    ctx = {}  # No repo_path

    remove_repo(ctx, mock_runner)

    # Should have checked for directory existence and then removed
    assert len(mock_runner.calls) >= 1, "Should have called at least one command"

    # Last call should be the rm command
    rm_calls = [c for c in mock_runner.calls if c[0] == 'run_shell' and 'rm' in ' '.join(c[1])]
    assert len(rm_calls) > 0, "Should have called rm command"


def test_clean_config_action_exists():
    """clean_config action should be importable"""
    from wizard.services.pagila.teardown_actions import clean_config
    assert callable(clean_config)


def test_clean_config_removes_pagila_section():
    """clean_config should remove pagila configuration"""
    from wizard.services.pagila.teardown_actions import clean_config

    mock_runner = MockActionRunner()
    ctx = {}

    clean_config(ctx, mock_runner)

    # Assert runner.save_config was called
    assert len(mock_runner.calls) == 1
    assert mock_runner.calls[0][0] == 'save_config'

    # Assert pagila config is set to disabled or removed
    config = mock_runner.calls[0][1]
    assert 'services' in config
    assert 'pagila' in config['services']
    # Should mark as disabled
    assert config['services']['pagila']['enabled'] is False


def test_clean_config_saves_to_correct_path():
    """clean_config should save to platform-config.yaml"""
    from wizard.services.pagila.teardown_actions import clean_config

    mock_runner = MockActionRunner()
    ctx = {}

    clean_config(ctx, mock_runner)

    # Assert saved to correct path
    assert mock_runner.calls[0][2] == 'platform-config.yaml'


# ============================================================================
# INTERFACE COMPLIANCE TESTS
# ============================================================================

def test_drop_database_signature_matches_interface():
    """Action must accept (ctx: Dict[str, Any], runner) signature."""
    from wizard.services.pagila.teardown_actions import drop_database
    import inspect

    sig = inspect.signature(drop_database)
    params = list(sig.parameters.keys())
    assert params == ['ctx', 'runner'], f"Expected ['ctx', 'runner'], got {params}"


def test_remove_repo_signature_matches_interface():
    """Action must accept (ctx: Dict[str, Any], runner) signature."""
    from wizard.services.pagila.teardown_actions import remove_repo
    import inspect

    sig = inspect.signature(remove_repo)
    params = list(sig.parameters.keys())
    assert params == ['ctx', 'runner'], f"Expected ['ctx', 'runner'], got {params}"


def test_clean_config_signature_matches_interface():
    """Action must accept (ctx: Dict[str, Any], runner) signature."""
    from wizard.services.pagila.teardown_actions import clean_config
    import inspect

    sig = inspect.signature(clean_config)
    params = list(sig.parameters.keys())
    assert params == ['ctx', 'runner'], f"Expected ['ctx', 'runner'], got {params}"


def test_all_actions_have_type_hints():
    """All action functions must have type hints."""
    from wizard.services.pagila.teardown_actions import (
        drop_database,
        remove_repo,
        clean_config
    )
    import inspect

    for action in [drop_database, remove_repo, clean_config]:
        sig = inspect.signature(action)

        # Check ctx parameter has type hint
        ctx_param = sig.parameters['ctx']
        assert ctx_param.annotation != inspect.Parameter.empty, \
            f"{action.__name__} 'ctx' parameter missing type hint"

        # Check return type hint exists
        assert sig.return_annotation != inspect.Signature.empty, \
            f"{action.__name__} missing return type hint"


def test_actions_use_runner_not_direct_io():
    """All actions must use runner interface, not direct I/O."""
    from wizard.services.pagila.teardown_actions import drop_database

    mock_runner = MockActionRunner()
    ctx = {}

    drop_database(ctx, mock_runner)

    # Verify runner was used
    assert len(mock_runner.calls) > 0
    assert mock_runner.calls[0][0] in ['run_shell', 'save_config']


# ============================================================================
# BUG FIX: Repository removal uses correct path
# ============================================================================

def test_remove_repo_discovers_actual_path_when_not_in_context():
    """remove_repo should discover the actual cloned repository path.

    BUG: When context doesn't have services.pagila.repo_path, teardown
    defaults to /tmp/pagila but actual clone is at ~/repos/pagila.

    FIX: Discovery should check both common locations:
    1. ~/repos/pagila (where setup-pagila.sh actually clones)
    2. /tmp/pagila (legacy/fallback location)
    """
    from wizard.services.pagila.teardown_actions import remove_repo
    import os

    mock_runner = MockActionRunner()

    # Simulate the bug: no repo_path in context
    ctx = {}

    # Mock file system checks to show ~/repos/pagila exists
    home_dir = os.path.expanduser('~')
    expected_path = os.path.join(home_dir, 'repos', 'pagila')

    # Mock runner should check for directory existence
    # Using the existing responses pattern from MockActionRunner
    mock_runner.responses['run_shell'] = {
        tuple(['test', '-d', expected_path]): {'returncode': 0, 'stdout': '', 'stderr': ''},
        tuple(['test', '-d', '/tmp/pagila']): {'returncode': 1, 'stdout': '', 'stderr': ''},
    }

    remove_repo(ctx, mock_runner)

    # Should have discovered and removed the correct path
    remove_calls = [c for c in mock_runner.calls if c[0] == 'run_shell' and 'rm' in ' '.join(c[1])]
    assert len(remove_calls) > 0, "Should have called rm command"

    remove_command = ' '.join(remove_calls[0][1])
    assert expected_path in remove_command, \
        f"Should remove {expected_path}, but command was: {remove_command}"
    assert '/tmp/pagila' not in remove_command, \
        "Should not try to remove /tmp/pagila when ~/repos/pagila exists"


def test_remove_repo_falls_back_to_tmp_when_repos_not_found():
    """remove_repo should fall back to /tmp/pagila if ~/repos/pagila doesn't exist."""
    from wizard.services.pagila.teardown_actions import remove_repo
    import os

    mock_runner = MockActionRunner()
    ctx = {}

    # Mock: ~/repos/pagila doesn't exist, but /tmp/pagila does
    home_dir = os.path.expanduser('~')
    repos_path = os.path.join(home_dir, 'repos', 'pagila')

    mock_runner.responses['run_shell'] = {
        tuple(['test', '-d', repos_path]): {'returncode': 1, 'stdout': '', 'stderr': ''},
        tuple(['test', '-d', '/tmp/pagila']): {'returncode': 0, 'stdout': '', 'stderr': ''},
    }

    remove_repo(ctx, mock_runner)

    # Should fall back to /tmp/pagila
    remove_calls = [c for c in mock_runner.calls if c[0] == 'run_shell' and 'rm' in ' '.join(c[1])]
    assert len(remove_calls) > 0

    remove_command = ' '.join(remove_calls[0][1])
    assert '/tmp/pagila' in remove_command, \
        "Should fall back to /tmp/pagila when ~/repos/pagila doesn't exist"


def test_remove_repo_handles_both_locations_missing():
    """remove_repo should gracefully handle when neither location exists."""
    from wizard.services.pagila.teardown_actions import remove_repo
    import os

    mock_runner = MockActionRunner()
    ctx = {}

    # Mock: neither location exists
    home_dir = os.path.expanduser('~')
    repos_path = os.path.join(home_dir, 'repos', 'pagila')

    mock_runner.responses['run_shell'] = {
        tuple(['test', '-d', repos_path]): {'returncode': 1, 'stdout': '', 'stderr': ''},
        tuple(['test', '-d', '/tmp/pagila']): {'returncode': 1, 'stdout': '', 'stderr': ''},
    }

    # Should not raise an error
    remove_repo(ctx, mock_runner)

    # Should still attempt to remove at least one location (with -f flag, it's safe)
    # Or should be a no-op - implementation choice
    # Current implementation will try to rm -rf anyway, which is safe with -f
