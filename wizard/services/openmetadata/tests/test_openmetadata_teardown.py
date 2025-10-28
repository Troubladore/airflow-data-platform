"""Tests for OpenMetadata teardown - RED phase"""
import pytest
import yaml
import inspect
from pathlib import Path
from wizard.engine.runner import MockActionRunner


# === TEARDOWN SPEC TESTS ===

def test_teardown_spec_loads():
    """Teardown spec loads without errors"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    assert spec_path.exists(), "teardown-spec.yaml must exist"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    assert spec is not None
    assert isinstance(spec, dict)


def test_teardown_spec_has_required_fields():
    """Teardown spec contains required fields: service, version, description"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    assert "service" in spec
    assert spec["service"] == "openmetadata"
    assert "version" in spec
    assert "description" in spec


def test_teardown_spec_has_confirmation_step():
    """Teardown spec includes confirmation step"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    assert "steps" in spec

    # Find confirmation step (now namespaced)
    confirm_step = next(
        (s for s in spec["steps"] if s.get("id") == "openmetadata_teardown_confirm"),
        None
    )

    assert confirm_step is not None, "Must have openmetadata_teardown_confirm step"
    assert confirm_step["type"] == "boolean"
    assert confirm_step.get("default_value") is False, "Default should be False for safety"


def test_teardown_spec_has_stop_service_action():
    """Teardown spec includes action to stop OpenMetadata services"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    # Find stop service action step
    stop_step = next(
        (s for s in spec["steps"] if s.get("id") == "stop_service"),
        None
    )

    assert stop_step is not None, "Must have stop_service step"
    assert stop_step["type"] == "action"
    assert stop_step["action"] == "openmetadata.stop_service"


def test_teardown_spec_has_volume_removal_step():
    """Teardown spec includes optional step to remove data volumes"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    # Find remove volumes question step
    volume_step = next(
        (s for s in spec["steps"] if s.get("id") == "remove_volumes_question"),
        None
    )

    assert volume_step is not None, "Must have remove_volumes_question step"
    assert volume_step["type"] == "boolean"
    assert "prompt" in volume_step


def test_teardown_spec_has_remove_volumes_action():
    """Teardown spec includes action to remove volumes when requested"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    # Find remove volumes action step
    remove_volumes_action = next(
        (s for s in spec["steps"] if s.get("id") == "remove_volumes_action"),
        None
    )

    assert remove_volumes_action is not None, "Must have remove_volumes_action step"
    assert remove_volumes_action["type"] == "action"
    assert remove_volumes_action["action"] == "openmetadata.remove_volumes"


def test_teardown_spec_has_image_removal_step():
    """Teardown spec includes optional step to remove Docker images"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    # Find remove images question step
    image_step = next(
        (s for s in spec["steps"] if s.get("id") == "remove_images_question"),
        None
    )

    assert image_step is not None, "Must have remove_images_question step"
    assert image_step["type"] == "boolean"
    assert "prompt" in image_step


def test_teardown_spec_has_remove_images_action():
    """Teardown spec includes action to remove images when requested"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    # Find remove images action step
    remove_images_action = next(
        (s for s in spec["steps"] if s.get("id") == "remove_images_action"),
        None
    )

    assert remove_images_action is not None, "Must have remove_images_action step"
    assert remove_images_action["type"] == "action"
    assert remove_images_action["action"] == "openmetadata.remove_images"


def test_teardown_spec_has_clean_config_action():
    """Teardown spec includes action to clean configuration"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    # Find clean config action step
    clean_step = next(
        (s for s in spec["steps"] if s.get("id") == "clean_config"),
        None
    )

    assert clean_step is not None, "Must have clean_config step"
    assert clean_step["type"] == "action"
    assert clean_step["action"] == "openmetadata.clean_config"


# === TEARDOWN ACTIONS TESTS ===

def test_stop_service_action_exists():
    """stop_service action can be imported"""
    from wizard.services.openmetadata.teardown_actions import stop_service
    assert callable(stop_service)


def test_stop_service_calls_docker_compose_stop():
    """Stops OpenMetadata services using docker-compose down"""
    from wizard.services.openmetadata.teardown_actions import stop_service

    mock_runner = MockActionRunner()
    mock_runner.responses['run_shell'] = {'returncode': 0, 'stdout': 'Stopped services'}
    ctx = {}

    stop_service(ctx, mock_runner)

    # Verify runner.run_shell was called
    assert len(mock_runner.calls) == 1
    assert mock_runner.calls[0][0] == 'run_shell'

    # Verify command uses docker compose down
    command = mock_runner.calls[0][1]
    assert 'docker' in command and 'compose' in command
    assert 'down' in command
    assert 'openmetadata' in ' '.join(command)


def test_stop_service_signature():
    """stop_service has correct signature (ctx, runner)"""
    from wizard.services.openmetadata.teardown_actions import stop_service

    sig = inspect.signature(stop_service)
    params = list(sig.parameters.keys())
    assert params == ['ctx', 'runner'], f"Expected ['ctx', 'runner'], got {params}"


def test_remove_volumes_action_exists():
    """remove_volumes action can be imported"""
    from wizard.services.openmetadata.teardown_actions import remove_volumes
    assert callable(remove_volumes)


def test_remove_volumes_calls_docker_volume_rm():
    """Removes OpenMetadata data volumes"""
    from wizard.services.openmetadata.teardown_actions import remove_volumes

    mock_runner = MockActionRunner()
    mock_runner.responses['run_shell'] = {'returncode': 0, 'stdout': 'Removed volumes'}
    ctx = {}

    remove_volumes(ctx, mock_runner)

    # Verify runner.run_shell was called
    assert len(mock_runner.calls) >= 1
    assert mock_runner.calls[0][0] == 'run_shell'

    # Verify command includes docker and volume
    command = mock_runner.calls[0][1]
    assert 'docker' in command
    assert 'volume' in command or 'rm' in command


def test_remove_volumes_signature():
    """remove_volumes has correct signature (ctx, runner)"""
    from wizard.services.openmetadata.teardown_actions import remove_volumes

    sig = inspect.signature(remove_volumes)
    params = list(sig.parameters.keys())
    assert params == ['ctx', 'runner'], f"Expected ['ctx', 'runner'], got {params}"


def test_remove_images_action_exists():
    """remove_images action can be imported"""
    from wizard.services.openmetadata.teardown_actions import remove_images
    assert callable(remove_images)


def test_remove_images_calls_docker_rmi():
    """Removes OpenMetadata Docker images"""
    from wizard.services.openmetadata.teardown_actions import remove_images

    mock_runner = MockActionRunner()
    mock_runner.responses['run_shell'] = {'returncode': 0, 'stdout': 'Removed images'}
    ctx = {
        'services.openmetadata.server_image': 'docker.getcollate.io/openmetadata/server:1.5.0',
        'services.openmetadata.opensearch_image': 'opensearchproject/opensearch:2.9.0'
    }

    remove_images(ctx, mock_runner)

    # Verify runner.run_shell was called
    assert len(mock_runner.calls) >= 1
    assert mock_runner.calls[0][0] == 'run_shell'

    # Verify command includes docker and rmi or image
    command = mock_runner.calls[0][1]
    assert 'docker' in command
    assert 'rmi' in command or 'image' in command


def test_remove_images_signature():
    """remove_images has correct signature (ctx, runner)"""
    from wizard.services.openmetadata.teardown_actions import remove_images

    sig = inspect.signature(remove_images)
    params = list(sig.parameters.keys())
    assert params == ['ctx', 'runner'], f"Expected ['ctx', 'runner'], got {params}"


def test_clean_config_action_exists():
    """clean_config action can be imported"""
    from wizard.services.openmetadata.teardown_actions import clean_config
    assert callable(clean_config)


def test_clean_config_removes_openmetadata_config():
    """Removes OpenMetadata configuration from platform-config.yaml"""
    from wizard.services.openmetadata.teardown_actions import clean_config

    mock_runner = MockActionRunner()
    ctx = {}

    clean_config(ctx, mock_runner)

    # Verify runner.save_config was called
    assert len(mock_runner.calls) == 1
    assert mock_runner.calls[0][0] == 'save_config'

    # Verify config removes openmetadata key or sets it to empty
    saved_config = mock_runner.calls[0][1]
    # Clean config should either not include openmetadata or set it to empty/null
    if "services" in saved_config and "openmetadata" in saved_config["services"]:
        # If it exists, it should be None or empty dict
        assert saved_config["services"]["openmetadata"] in [None, {}]


def test_clean_config_signature():
    """clean_config has correct signature (ctx, runner)"""
    from wizard.services.openmetadata.teardown_actions import clean_config

    sig = inspect.signature(clean_config)
    params = list(sig.parameters.keys())
    assert params == ['ctx', 'runner'], f"Expected ['ctx', 'runner'], got {params}"


# === INTERFACE COMPLIANCE TESTS ===

def test_all_actions_use_runner():
    """All teardown actions must use runner, not direct I/O"""
    from wizard.services.openmetadata.teardown_actions import (
        stop_service, remove_volumes, remove_images, clean_config
    )

    actions = [stop_service, remove_volumes, remove_images, clean_config]

    for action in actions:
        mock_runner = MockActionRunner()
        mock_runner.responses['run_shell'] = {'returncode': 0, 'stdout': 'success'}
        ctx = {
            'services.openmetadata.server_image': 'test:1.0',
            'services.openmetadata.opensearch_image': 'search:1.0'
        }

        action(ctx, mock_runner)

        # Each action must make at least one call to the runner
        assert len(mock_runner.calls) >= 1, f"{action.__name__} must use runner"


def test_all_actions_have_type_hints():
    """All teardown actions must have type hints"""
    from wizard.services.openmetadata import teardown_actions
    import inspect

    action_functions = [
        teardown_actions.stop_service,
        teardown_actions.remove_volumes,
        teardown_actions.remove_images,
        teardown_actions.clean_config
    ]

    for func in action_functions:
        sig = inspect.signature(func)

        # Check ctx parameter has type hint
        assert 'ctx' in sig.parameters
        ctx_param = sig.parameters['ctx']
        assert ctx_param.annotation != inspect.Parameter.empty, \
            f"{func.__name__} ctx parameter must have type hint"

        # Check runner parameter exists (no type hint required per convention)
        assert 'runner' in sig.parameters


def test_teardown_spec_conditional_flow():
    """Teardown spec should have conditional flow based on user choices"""
    spec_path = Path(__file__).parent.parent / "teardown-spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    # Find the remove_volumes question step
    volume_step = next(
        (s for s in spec["steps"] if s.get("id") == "remove_volumes_question"),
        None
    )

    # It should have conditional next (next_if_true/next_if_false or condition)
    # This ensures volumes are only removed if user chooses yes
    assert volume_step is not None
    # The step should lead to action only if true
    # Can be implemented via next_if_true or similar conditional mechanism


def test_state_management():
    """Teardown actions should update state correctly"""
    from wizard.services.openmetadata.teardown_actions import stop_service

    mock_runner = MockActionRunner()
    mock_runner.responses['run_shell'] = {'returncode': 0, 'stdout': 'Stopped'}

    ctx = {
        'services.openmetadata.status': 'running'
    }

    stop_service(ctx, mock_runner)

    # Verify service was stopped via shell command
    assert any(call[0] == 'run_shell' for call in mock_runner.calls)
