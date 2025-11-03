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


# ============================================================================
# BRANCH SELECTION SPEC TESTS - RED PHASE
# ============================================================================

def test_spec_has_branch_step():
    """spec.yaml should have a step for collecting repository branch"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])
    step_ids = [step.get('id') for step in steps]

    # Should have a step for branch
    assert any('branch' in str(step_id).lower() for step_id in step_ids), \
        f"No branch step found in step IDs: {step_ids}"


def test_spec_branch_step_is_optional():
    """Branch step should be optional with a default value"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find branch step
    branch_step = None
    for step in steps:
        if 'branch' in str(step.get('id', '')).lower():
            branch_step = step
            break

    assert branch_step is not None, "No branch step found"

    # Should have a default value (empty string means default branch)
    assert 'default_value' in branch_step, "Branch step should have default_value"


def test_spec_branch_step_saves_to_state():
    """Branch step should save value to state_key"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find branch step
    branch_step = None
    for step in steps:
        if 'branch' in str(step.get('id', '')).lower():
            branch_step = step
            break

    assert branch_step is not None, "No branch step found"
    assert 'state_key' in branch_step, "Branch step should have state_key"
    assert 'services.pagila.branch' in branch_step['state_key'], \
        f"Branch state_key should be 'services.pagila.branch', got: {branch_step.get('state_key')}"


def test_spec_branch_step_comes_after_repo_url():
    """Branch step should come after repository URL step in workflow"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])
    step_ids = [step.get('id') for step in steps]

    # Find indices
    repo_index = None
    branch_index = None

    for i, step_id in enumerate(step_ids):
        if 'repo' in str(step_id).lower() and 'url' in str(step_id).lower():
            repo_index = i
        if 'branch' in str(step_id).lower():
            branch_index = i

    assert repo_index is not None, "No repo URL step found"
    assert branch_index is not None, "No branch step found"
    assert branch_index > repo_index, \
        f"Branch step (index {branch_index}) should come after repo URL step (index {repo_index})"


# ============================================================================
# PAGILA TEST CONTAINER SPEC TESTS - RED PHASE
# ============================================================================

def test_spec_has_pagila_test_prebuilt_step():
    """spec.yaml should have a step for pagila_test prebuilt configuration"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])
    step_ids = [step.get('id') for step in steps]

    # Should have a step for pagila test prebuilt configuration
    assert 'pagila_test_prebuilt' in step_ids, \
        f"No pagila_test_prebuilt step found in step IDs: {step_ids}"


def test_spec_has_pagila_test_image_step():
    """spec.yaml should have a step for pagila_test image configuration"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])
    step_ids = [step.get('id') for step in steps]

    # Should have a step for pagila test image
    assert 'pagila_test_image' in step_ids, \
        f"No pagila_test_image step found in step IDs: {step_ids}"


def test_spec_pagila_test_prebuilt_step_configuration():
    """pagila_test_prebuilt step should be properly configured"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find pagila_test_prebuilt step
    prebuilt_step = None
    for step in steps:
        if step.get('id') == 'pagila_test_prebuilt':
            prebuilt_step = step
            break

    assert prebuilt_step is not None, "pagila_test_prebuilt step not found"
    assert prebuilt_step['type'] == 'boolean', "Should be a boolean type"
    assert 'state_key' in prebuilt_step, "Should have state_key"
    assert prebuilt_step['state_key'] == 'services.pagila.test_containers.pagila_test.use_prebuilt'
    assert prebuilt_step.get('default_value') == False, "Should default to False"
    assert 'prompt' in prebuilt_step, "Should have a prompt"
    assert 'next' in prebuilt_step, "Should have next step defined"


def test_spec_pagila_test_image_step_configuration():
    """pagila_test_image step should be properly configured"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find pagila_test_image step
    image_step = None
    for step in steps:
        if step.get('id') == 'pagila_test_image':
            image_step = step
            break

    assert image_step is not None, "pagila_test_image step not found"
    assert image_step['type'] == 'string', "Should be a string type"
    assert 'state_key' in image_step, "Should have state_key"
    assert image_step['state_key'] == 'services.pagila.test_containers.pagila_test.image'
    assert image_step.get('default_value') == 'alpine:latest', "Should default to alpine:latest"
    assert 'validator' in image_step, "Should have image URL validator"
    assert 'validate' in image_step['validator'] and 'image' in image_step['validator']
    assert 'prompt' in image_step, "Should have a prompt"
    assert 'next' in image_step, "Should have next step defined"


def test_spec_has_save_pagila_test_config_step():
    """spec.yaml should have a step that saves pagila test configuration"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])
    step_ids = [step.get('id') for step in steps]

    # Should have a pagila_save_test_config step
    assert 'pagila_save_test_config' in step_ids, \
        f"No pagila_save_test_config step found in step IDs: {step_ids}"


def test_spec_save_pagila_test_config_step_configuration():
    """pagila_save_test_config step should be properly configured"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find pagila_save_test_config step
    save_step = None
    for step in steps:
        if step.get('id') == 'pagila_save_test_config':
            save_step = step
            break

    assert save_step is not None, "pagila_save_test_config step not found"
    assert save_step['type'] == 'action', "Should be an action type"
    assert save_step['action'] == 'pagila.save_pagila_test_config'
    assert 'next' in save_step, "Should have next step defined"


def test_spec_has_verify_pagila_connection_step():
    """spec.yaml should have a step that verifies Pagila connection"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])
    step_ids = [step.get('id') for step in steps]

    # Should have a pagila_verify_connection step
    assert 'pagila_verify_connection' in step_ids, \
        f"No pagila_verify_connection step found in step IDs: {step_ids}"


def test_spec_verify_pagila_connection_step_configuration():
    """pagila_verify_connection step should be properly configured"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find pagila_verify_connection step
    verify_step = None
    for step in steps:
        if step.get('id') == 'pagila_verify_connection':
            verify_step = step
            break

    assert verify_step is not None, "pagila_verify_connection step not found"
    assert verify_step['type'] == 'action', "Should be an action type"
    assert verify_step['action'] == 'pagila.verify_pagila_connection'
    assert 'next' in verify_step, "Should have next step defined"


def test_spec_test_container_flow_after_pagila_install():
    """Test container configuration should follow pagila_install in the flow"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = {s['id']: s for s in spec['steps']}

    # pagila_install should lead to pagila_test_prebuilt
    assert 'pagila_install' in steps, "pagila_install step not found"
    install_step = steps['pagila_install']
    assert install_step.get('next') == 'pagila_test_prebuilt', \
        f"pagila_install should lead to pagila_test_prebuilt, but leads to {install_step.get('next')}"

    # pagila_test_prebuilt should lead to pagila_test_image
    assert 'pagila_test_prebuilt' in steps, "pagila_test_prebuilt step not found"
    prebuilt_step = steps['pagila_test_prebuilt']
    assert prebuilt_step.get('next') == 'pagila_test_image', \
        f"pagila_test_prebuilt should lead to pagila_test_image, but leads to {prebuilt_step.get('next')}"

    # pagila_test_image should lead to pagila_save_test_config
    assert 'pagila_test_image' in steps, "pagila_test_image step not found"
    image_step = steps['pagila_test_image']
    assert image_step.get('next') == 'pagila_save_test_config', \
        f"pagila_test_image should lead to pagila_save_test_config, but leads to {image_step.get('next')}"

    # pagila_save_test_config should lead to pagila_verify_connection
    assert 'pagila_save_test_config' in steps, "pagila_save_test_config step not found"
    save_step = steps['pagila_save_test_config']
    assert save_step.get('next') == 'pagila_verify_connection', \
        f"pagila_save_test_config should lead to pagila_verify_connection, but leads to {save_step.get('next')}"

    # pagila_verify_connection should lead to finish
    assert 'pagila_verify_connection' in steps, "pagila_verify_connection step not found"
    verify_step = steps['pagila_verify_connection']
    assert verify_step.get('next') == 'finish', \
        f"pagila_verify_connection should lead to finish, but leads to {verify_step.get('next')}"
