"""Tests for Pagila service spec - RED phase"""
import pytest
import yaml
from pathlib import Path


def test_spec_file_exists():
    """spec.yaml file should exist in pagila service directory"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"
    assert spec_path.exists(), "spec.yaml file not found"


def test_spec_loads_as_valid_yaml():
    """spec.yaml should be valid YAML that can be loaded"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert spec is not None
    assert isinstance(spec, dict)


def test_spec_has_service_name():
    """spec.yaml should declare service name as 'pagila'"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert 'service' in spec
    assert spec['service'] == 'pagila'


def test_spec_has_version():
    """spec.yaml should declare a version"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert 'version' in spec
    assert isinstance(spec['version'], (str, float))


def test_spec_has_description():
    """spec.yaml should have a description"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert 'description' in spec
    assert len(spec['description']) > 0


def test_spec_requires_postgres():
    """spec.yaml should declare dependency on db.postgres"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert 'requires' in spec
    assert isinstance(spec['requires'], list)
    assert 'db.postgres' in spec['requires']


def test_spec_provides_sample_data():
    """spec.yaml should declare it provides sample.pagila capability"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert 'provides' in spec
    assert isinstance(spec['provides'], list)
    assert 'sample.pagila' in spec['provides']


def test_spec_has_steps():
    """spec.yaml should define conversation steps"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert 'steps' in spec
    assert isinstance(spec['steps'], list)
    assert len(spec['steps']) > 0


def test_spec_has_repo_url_step():
    """spec.yaml should have a step for collecting repository URL"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    # Find a step with repo_url or similar
    steps = spec.get('steps', [])
    step_ids = [step.get('id') for step in steps]

    # Should have a step for repository URL
    assert any('repo' in str(step_id).lower() for step_id in step_ids)


def test_spec_repo_step_has_validator():
    """Repository URL step should have a validator"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find repo URL step
    repo_step = None
    for step in steps:
        if 'repo' in str(step.get('id', '')).lower():
            repo_step = step
            break

    assert repo_step is not None, "No repo URL step found"
    assert 'validator' in repo_step
    assert 'validate_git_url' in repo_step['validator']


def test_spec_has_save_action_step():
    """spec.yaml should have a step that saves configuration"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Should have an action step with save_config
    action_steps = [step for step in steps if step.get('type') == 'action']
    assert len(action_steps) > 0

    save_steps = [step for step in action_steps if 'save' in step.get('action', '').lower()]
    assert len(save_steps) > 0


def test_spec_has_install_action_step():
    """spec.yaml should have a step that installs Pagila"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Should have an action step with install
    action_steps = [step for step in steps if step.get('type') == 'action']
    install_steps = [step for step in action_steps if 'install' in step.get('action', '').lower()]

    assert len(install_steps) > 0


def test_spec_step_ids_are_namespaced():
    """All step IDs should be namespaced with 'pagila_' prefix"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    for step in steps:
        step_id = step.get('id', '')
        # Skip 'finish' as it's a common endpoint
        if step_id != 'finish':
            assert step_id.startswith('pagila_'), f"Step ID '{step_id}' not namespaced"


def test_spec_actions_are_namespaced():
    """All action references should be namespaced with 'pagila.' prefix"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    for step in steps:
        if 'action' in step:
            action = step['action']
            assert action.startswith('pagila.'), f"Action '{action}' not namespaced"


def test_spec_validators_are_namespaced():
    """All validator references should be namespaced with 'pagila.' prefix"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    for step in steps:
        if 'validator' in step:
            validator = step['validator']
            assert validator.startswith('pagila.'), f"Validator '{validator}' not namespaced"
