"""Tests for Kerberos service spec - RED phase"""
import pytest
import yaml
from pathlib import Path


def test_spec_file_exists():
    """Kerberos spec.yaml file exists"""
    spec_path = Path(__file__).parent.parent / 'spec.yaml'
    assert spec_path.exists(), f"spec.yaml not found at {spec_path}"


def test_spec_loads_as_valid_yaml():
    """spec.yaml loads as valid YAML"""
    spec_path = Path(__file__).parent.parent / 'spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert spec is not None
    assert isinstance(spec, dict)


def test_spec_has_required_fields():
    """spec.yaml contains required service metadata"""
    spec_path = Path(__file__).parent.parent / 'spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert 'service' in spec
    assert spec['service'] == 'kerberos'
    assert 'version' in spec
    assert 'description' in spec
    assert 'steps' in spec


def test_spec_has_domain_input_step():
    """spec.yaml includes step for domain input"""
    spec_path = Path(__file__).parent.parent / 'spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])
    assert len(steps) > 0

    # Find domain input step
    domain_step = None
    for step in steps:
        if 'domain' in step.get('state_key', '').lower() or \
           'domain' in step.get('id', '').lower():
            domain_step = step
            break

    assert domain_step is not None, "No domain input step found"
    assert domain_step.get('type') == 'string'
    assert 'state_key' in domain_step
    assert 'kerberos' in domain_step['state_key']


def test_spec_has_image_input_step():
    """spec.yaml includes step for Docker image input"""
    spec_path = Path(__file__).parent.parent / 'spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find image input step
    image_step = None
    for step in steps:
        if 'image' in step.get('state_key', '').lower() or \
           'image' in step.get('id', '').lower():
            image_step = step
            break

    assert image_step is not None, "No image input step found"
    assert image_step.get('type') == 'string'


def test_spec_has_domain_validator():
    """spec.yaml domain step has validator"""
    spec_path = Path(__file__).parent.parent / 'spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find domain step and check validator
    domain_step = None
    for step in steps:
        if 'domain' in step.get('state_key', '').lower():
            domain_step = step
            break

    assert domain_step is not None
    assert 'validator' in domain_step
    assert 'validate_domain' in domain_step['validator']


def test_spec_has_test_kerberos_action():
    """spec.yaml includes test_kerberos action step"""
    spec_path = Path(__file__).parent.parent / 'spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find action step that tests Kerberos
    test_action = None
    for step in steps:
        if step.get('type') == 'action' and \
           'test' in step.get('action', '').lower():
            test_action = step
            break

    assert test_action is not None, "No test_kerberos action found"
    assert 'action' in test_action
    assert 'test_kerberos' in test_action['action']


def test_spec_has_save_config_action():
    """spec.yaml includes save_config action step"""
    spec_path = Path(__file__).parent.parent / 'spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    steps = spec.get('steps', [])

    # Find save_config action
    save_action = None
    for step in steps:
        if step.get('type') == 'action' and \
           'save' in step.get('action', '').lower():
            save_action = step
            break

    assert save_action is not None, "No save_config action found"


def test_spec_provides_kerberos_capability():
    """spec.yaml declares it provides kerberos capability"""
    spec_path = Path(__file__).parent.parent / 'spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert 'provides' in spec
    provides = spec['provides']
    assert isinstance(provides, list)
    assert any('kerberos' in p for p in provides)


def test_spec_requires_empty_or_list():
    """spec.yaml has valid requires field (empty or list)"""
    spec_path = Path(__file__).parent.parent / 'spec.yaml'

    with open(spec_path, 'r') as f:
        spec = yaml.safe_load(f)

    assert 'requires' in spec
    requires = spec['requires']
    assert isinstance(requires, list)
