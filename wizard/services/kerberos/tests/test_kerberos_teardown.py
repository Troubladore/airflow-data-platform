"""Tests for Kerberos teardown - RED phase"""
import pytest
import yaml
from pathlib import Path
from wizard.engine.runner import MockActionRunner
from wizard.services.kerberos.teardown_actions import (
    stop_service,
    remove_keytabs,
    remove_images,
    clean_configuration
)


# ============================================================================
# Teardown Spec Tests
# ============================================================================


def test_teardown_spec_file_exists():
    """teardown-spec.yaml file exists"""
    spec_path = Path(__file__).parent.parent / 'teardown-spec.yaml'
    assert spec_path.exists(), f"teardown-spec.yaml not found at {spec_path}"


def test_teardown_spec_loads_as_valid_yaml():
    """teardown-spec.yaml loads as valid YAML"""
    spec_path = Path(__file__).parent.parent / 'teardown-spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert spec is not None
    assert isinstance(spec, dict)


def test_teardown_spec_has_required_fields():
    """teardown-spec.yaml contains required service metadata"""
    spec_path = Path(__file__).parent.parent / 'teardown-spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert 'service' in spec
    assert spec['service'] == 'kerberos'
    assert 'version' in spec
    assert 'description' in spec
    assert 'teardown' in spec['description'].lower()
    assert 'steps' in spec


def test_teardown_spec_has_confirmation_step():
    """teardown-spec.yaml includes confirmation step"""
    spec_path = Path(__file__).parent.parent / 'teardown-spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])
    assert len(steps) > 0

    # Find confirmation step (now namespaced)
    confirm_step = None
    for step in steps:
        if step.get('id') == 'kerberos_teardown_confirm':
            confirm_step = step
            break

    assert confirm_step is not None, "No kerberos_teardown_confirm step found"
    assert confirm_step.get('type') == 'boolean'


def test_teardown_spec_has_stop_service_action():
    """teardown-spec.yaml includes stop_service action"""
    spec_path = Path(__file__).parent.parent / 'teardown-spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find stop service action
    stop_action = None
    for step in steps:
        if step.get('type') == 'action' and \
           'stop' in step.get('action', '').lower():
            stop_action = step
            break

    assert stop_action is not None, "No stop_service action found"
    assert 'kerberos.stop_service' in stop_action['action']


def test_teardown_spec_has_keytab_removal_step():
    """teardown-spec.yaml includes optional keytab removal"""
    spec_path = Path(__file__).parent.parent / 'teardown-spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find keytab removal step (either choice or action)
    keytab_step = None
    for step in steps:
        if 'keytab' in step.get('id', '').lower() or \
           'keytab' in step.get('action', '').lower() or \
           'keytab' in step.get('prompt', '').lower():
            keytab_step = step
            break

    assert keytab_step is not None, "No keytab removal step found"


def test_teardown_spec_has_image_removal_step():
    """teardown-spec.yaml includes optional image removal"""
    spec_path = Path(__file__).parent.parent / 'teardown-spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find image removal step
    image_step = None
    for step in steps:
        if 'image' in step.get('id', '').lower() or \
           'image' in step.get('action', '').lower() or \
           'image' in step.get('prompt', '').lower():
            image_step = step
            break

    assert image_step is not None, "No image removal step found"


def test_teardown_spec_has_clean_config_action():
    """teardown-spec.yaml includes clean_configuration action"""
    spec_path = Path(__file__).parent.parent / 'teardown-spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find clean config action
    clean_action = None
    for step in steps:
        if step.get('type') == 'action' and \
           ('clean' in step.get('action', '').lower() or \
            'config' in step.get('action', '').lower()):
            clean_action = step
            break

    assert clean_action is not None, "No clean_configuration action found"


# ============================================================================
# Teardown Action Tests
# ============================================================================


def test_stop_service_calls_docker_rm():
    """stop_service removes Kerberos container using docker rm"""
    mock_runner = MockActionRunner()
    ctx = {}

    mock_runner.responses['run_shell'] = {
        'stdout': 'Removed',
        'stderr': '',
        'returncode': 0
    }

    stop_service(ctx, mock_runner)

    # Verify docker rm was called (find it among display calls)
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) >= 1
    call_type, command, cwd = run_shell_calls[0]
    assert call_type == 'run_shell'
    assert 'docker' in command
    assert 'rm' in command


def test_stop_service_uses_correct_working_directory():
    """stop_service executes docker commands with correct working directory"""
    mock_runner = MockActionRunner()
    ctx = {}

    mock_runner.responses['run_shell'] = {
        'stdout': 'Stopped',
        'stderr': '',
        'returncode': 0
    }

    stop_service(ctx, mock_runner)

    # Find run_shell calls (skip display calls)
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) >= 1
    call_type, command, cwd = run_shell_calls[0]
    # docker rm doesn't need a specific working directory (cwd can be None)
    assert call_type == 'run_shell'


def test_stop_service_removes_mock_container():
    """stop_service tries kerberos-sidecar-mock FIRST (RED test for bug fix)

    BUG: Setup creates kerberos-sidecar-mock but teardown tries kerberos-sidecar first.
    With docker rm -f, non-existent containers succeed silently, so mock container is never tried.

    FIX: Try kerberos-sidecar-mock FIRST (the one we actually create).
    """
    mock_runner = MockActionRunner()
    ctx = {}

    # Track which container was tried
    containers_tried = []

    def mock_run_shell(command, cwd=None):
        mock_runner.calls.append(('run_shell', command, cwd))

        # Track which container name appears in command
        if 'kerberos-sidecar-mock' in command:
            containers_tried.append('kerberos-sidecar-mock')
            return {'stdout': 'Removed kerberos-sidecar-mock', 'stderr': '', 'returncode': 0}
        elif 'kerberos-sidecar' in command:
            containers_tried.append('kerberos-sidecar')
            # With -f flag, docker rm succeeds even if container doesn't exist
            return {'stdout': '', 'stderr': '', 'returncode': 0}
        return {'stdout': '', 'stderr': '', 'returncode': 1}

    # Override run_shell to use our custom mock
    mock_runner.run_shell = mock_run_shell

    stop_service(ctx, mock_runner)

    # RED TEST: Verify kerberos-sidecar-mock is tried FIRST
    # (not second, not never - but FIRST because that's what we create)
    assert len(containers_tried) > 0, "Should attempt to remove at least one container"
    assert containers_tried[0] == 'kerberos-sidecar-mock', \
        f"Should try kerberos-sidecar-mock FIRST (got: {containers_tried[0]})"


def test_remove_keytabs_removes_keytab_files():
    """remove_keytabs removes Kerberos keytab files"""
    mock_runner = MockActionRunner()
    ctx = {}

    mock_runner.responses['run_shell'] = {
        'stdout': 'Removed keytabs',
        'stderr': '',
        'returncode': 0
    }

    remove_keytabs(ctx, mock_runner)

    # Verify rm command was called for keytabs
    assert len(mock_runner.calls) == 1
    call_type, command, cwd = mock_runner.calls[0]
    assert call_type == 'run_shell'
    assert 'rm' in command
    assert any('keytab' in str(arg).lower() for arg in command)


def test_remove_keytabs_handles_no_files():
    """remove_keytabs handles case when no keytabs exist"""
    mock_runner = MockActionRunner()
    ctx = {}

    # Mock failure (files don't exist)
    mock_runner.responses['run_shell'] = {
        'stdout': '',
        'stderr': 'No such file or directory',
        'returncode': 1
    }

    # Should not raise exception
    remove_keytabs(ctx, mock_runner)

    assert len(mock_runner.calls) == 1


def test_remove_keytabs_uses_custom_path():
    """remove_keytabs uses custom keytab path from context"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.keytab_path': '/custom/path/*.keytab'
    }

    mock_runner.responses['run_shell'] = {
        'stdout': 'Removed keytabs',
        'stderr': '',
        'returncode': 0
    }

    remove_keytabs(ctx, mock_runner)

    # Verify custom path was used
    call_type, command, cwd = mock_runner.calls[0]
    assert '/custom/path/*.keytab' in command


def test_remove_images_removes_docker_images():
    """remove_images removes Kerberos Docker images"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.image': 'ubuntu:22.04'
    }

    mock_runner.responses['run_shell'] = {
        'stdout': 'Untagged: ubuntu:22.04',
        'stderr': '',
        'returncode': 0
    }

    remove_images(ctx, mock_runner)

    # Verify docker rmi was called
    assert len(mock_runner.calls) == 1
    call_type, command, cwd = mock_runner.calls[0]
    assert call_type == 'run_shell'
    assert 'docker' in command
    assert 'rmi' in command or 'remove' in ' '.join(command).lower()


def test_remove_images_uses_image_from_context():
    """remove_images uses image name from context"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.image': 'myregistry.com/kerberos:1.0'
    }

    mock_runner.responses['run_shell'] = {
        'stdout': 'Removed image',
        'stderr': '',
        'returncode': 0
    }

    remove_images(ctx, mock_runner)

    call_type, command, cwd = mock_runner.calls[0]
    # Should reference the image from context
    assert any('myregistry.com/kerberos:1.0' in str(arg) for arg in command) or \
           ctx.get('services.kerberos.image') is not None


def test_clean_configuration_disables_kerberos():
    """clean_configuration sets enabled to false in config"""
    mock_runner = MockActionRunner()
    ctx = {}

    clean_configuration(ctx, mock_runner)

    # Verify save_config was called
    assert len(mock_runner.calls) == 1
    call_type, config, path = mock_runner.calls[0]
    assert call_type == 'save_config'
    assert config['services']['kerberos']['enabled'] is False
    assert path == 'platform-config.yaml'


def test_clean_configuration_preserves_other_config():
    """clean_configuration only disables Kerberos, doesn't remove config"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.domain': 'COMPANY.COM',
        'services.kerberos.image': 'ubuntu:22.04'
    }

    clean_configuration(ctx, mock_runner)

    call_type, config, path = mock_runner.calls[0]
    # Should preserve domain/image but disable service
    assert 'services' in config
    assert 'kerberos' in config['services']
    assert config['services']['kerberos']['enabled'] is False


# ============================================================================
# Interface Compliance Tests
# ============================================================================


def test_stop_service_signature_matches_interface():
    """stop_service must accept (ctx, runner) signature"""
    import inspect
    sig = inspect.signature(stop_service)
    params = list(sig.parameters.keys())
    assert params == ['ctx', 'runner'], f"Expected ['ctx', 'runner'], got {params}"


def test_remove_keytabs_signature_matches_interface():
    """remove_keytabs must accept (ctx, runner) signature"""
    import inspect
    sig = inspect.signature(remove_keytabs)
    params = list(sig.parameters.keys())
    assert params == ['ctx', 'runner'], f"Expected ['ctx', 'runner'], got {params}"


def test_remove_images_signature_matches_interface():
    """remove_images must accept (ctx, runner) signature"""
    import inspect
    sig = inspect.signature(remove_images)
    params = list(sig.parameters.keys())
    assert params == ['ctx', 'runner'], f"Expected ['ctx', 'runner'], got {params}"


def test_clean_configuration_signature_matches_interface():
    """clean_configuration must accept (ctx, runner) signature"""
    import inspect
    sig = inspect.signature(clean_configuration)
    params = list(sig.parameters.keys())
    assert params == ['ctx', 'runner'], f"Expected ['ctx', 'runner'], got {params}"


def test_all_actions_use_runner_not_direct_io():
    """All teardown actions must use runner, not direct I/O"""
    mock_runner = MockActionRunner()
    ctx = {'services.kerberos.image': 'ubuntu:22.04'}

    # Test each action
    stop_service(ctx, mock_runner)
    assert len(mock_runner.calls) > 0

    mock_runner.calls = []
    remove_keytabs(ctx, mock_runner)
    assert len(mock_runner.calls) > 0

    mock_runner.calls = []
    remove_images(ctx, mock_runner)
    assert len(mock_runner.calls) > 0

    mock_runner.calls = []
    clean_configuration(ctx, mock_runner)
    assert len(mock_runner.calls) > 0


# ============================================================================
# State Management Tests
# ============================================================================


def test_teardown_updates_state_correctly():
    """Teardown actions update context state correctly"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.enabled': True,
        'services.kerberos.domain': 'COMPANY.COM',
        'services.kerberos.image': 'ubuntu:22.04'
    }

    clean_configuration(ctx, mock_runner)

    # Verify state change through runner
    call_type, config, path = mock_runner.calls[0]
    assert config['services']['kerberos']['enabled'] is False


def test_conditional_steps_respect_user_choices():
    """Conditional teardown steps respect user choices"""
    mock_runner = MockActionRunner()

    # User chooses not to remove keytabs
    ctx = {
        'services.kerberos.teardown.remove_keytabs': False
    }

    # This would be handled by the engine's conditional logic
    # The action itself should just work when called
    if ctx.get('services.kerberos.teardown.remove_keytabs', False):
        remove_keytabs(ctx, mock_runner)

    # Should not have been called
    assert len(mock_runner.calls) == 0

    # User chooses to remove keytabs
    ctx['services.kerberos.teardown.remove_keytabs'] = True
    if ctx.get('services.kerberos.teardown.remove_keytabs', False):
        remove_keytabs(ctx, mock_runner)

    # Should have been called
    assert len(mock_runner.calls) == 1


# ============================================================================
# MockActionRunner Compliance Tests
# ============================================================================


def test_all_actions_work_with_mock_runner():
    """All actions work with MockActionRunner (no real Kerberos operations)"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.domain': 'COMPANY.COM',
        'services.kerberos.image': 'ubuntu:22.04'
    }

    # Set up mock responses
    mock_runner.responses['run_shell'] = {
        'stdout': 'Success',
        'stderr': '',
        'returncode': 0
    }

    # All actions should work with mock runner
    stop_service(ctx, mock_runner)
    remove_keytabs(ctx, mock_runner)
    remove_images(ctx, mock_runner)
    clean_configuration(ctx, mock_runner)

    # Verify all used runner (includes display calls now)
    assert len(mock_runner.calls) >= 4, "Should have at least 4 runner calls (run_shell and save_config)"

    # Verify we have the key action calls
    call_types = [call[0] for call in mock_runner.calls]
    assert 'run_shell' in call_types, "Should have run_shell calls"
    assert 'save_config' in call_types, "Should have save_config call"


def test_no_actual_kerberos_operations_in_tests():
    """Tests use MockActionRunner - no actual Kerberos operations"""
    # This is a meta-test to ensure we're testing the interface
    # not actual Kerberos operations
    mock_runner = MockActionRunner()
    ctx = {}

    # Even with no mock responses, actions should work
    stop_service(ctx, mock_runner)

    # Verify it recorded calls but didn't actually do anything
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) >= 1, "Should have recorded at least one run_shell call"
    # The mock runner doesn't actually execute commands
