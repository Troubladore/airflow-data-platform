"""Tests for SpecLoader - YAML loading and validation."""

import pytest
import tempfile
import os
from pathlib import Path
from wizard.engine.loader import SpecLoader
from wizard.engine.schema import ServiceSpec, Flow


@pytest.fixture
def temp_dir():
    """Create temporary directory for test fixtures."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)


@pytest.fixture
def sample_service_yaml(temp_dir):
    """Create a sample service spec YAML file."""
    service_dir = temp_dir / "wizard" / "services" / "postgres"
    service_dir.mkdir(parents=True)

    spec_content = """
service: postgres
version: "1.0"
description: PostgreSQL database configuration
requires: []
provides:
  - db.postgres
steps:
  - id: postgres_image
    type: string
    prompt: "PostgreSQL image:"
    state_key: services.postgres.image
    default_value: postgres:17.5-alpine
    next: postgres_auth
  - id: postgres_auth
    type: enum
    prompt: "Authentication mode:"
    state_key: services.postgres.auth_method
    options:
      - value: trust
        label: "Passwordless"
      - value: md5
        label: "Password"
    next: finish
  - id: finish
    type: display
    prompt: "Configuration complete"
"""
    spec_file = service_dir / "spec.yaml"
    spec_file.write_text(spec_content)
    return spec_file


@pytest.fixture
def sample_flow_yaml(temp_dir):
    """Create a sample flow YAML file."""
    flow_dir = temp_dir / "wizard" / "flows"
    flow_dir.mkdir(parents=True)

    flow_content = """
name: setup
version: "1.0"
description: Platform setup wizard
service_selection:
  - id: select_postgres
    type: boolean
    prompt: "Enable PostgreSQL?"
    state_key: services.postgres.enabled
    next: configure_services
targets:
  - service: postgres
    required: true
  - service: openmetadata
    condition: services.openmetadata.enabled == true
    requires:
      - db.postgres
"""
    flow_file = flow_dir / "setup.yaml"
    flow_file.write_text(flow_content)
    return flow_file


def test_loader_load_service_spec(temp_dir, sample_service_yaml):
    """SpecLoader can load and validate a service spec."""
    loader = SpecLoader(base_path=temp_dir / "wizard")

    spec = loader.load_service_spec('postgres')

    assert isinstance(spec, ServiceSpec)
    assert spec.service == 'postgres'
    assert spec.version == '1.0'
    assert spec.provides == ['db.postgres']
    assert len(spec.steps) == 3
    assert spec.steps[0].id == 'postgres_image'


def test_loader_load_flow(temp_dir, sample_flow_yaml):
    """SpecLoader can load and validate a flow."""
    loader = SpecLoader(base_path=temp_dir / "wizard")

    flow = loader.load_flow('setup')

    assert isinstance(flow, Flow)
    assert flow.name == 'setup'
    assert flow.version == '1.0'
    assert len(flow.targets) == 2
    assert flow.targets[0]['service'] == 'postgres'
    assert flow.targets[0]['required'] is True


def test_loader_service_not_found(temp_dir):
    """SpecLoader raises error for non-existent service."""
    loader = SpecLoader(base_path=temp_dir / "wizard")

    with pytest.raises(FileNotFoundError) as exc_info:
        loader.load_service_spec('nonexistent')

    assert 'nonexistent' in str(exc_info.value)


def test_loader_flow_not_found(temp_dir):
    """SpecLoader raises error for non-existent flow."""
    loader = SpecLoader(base_path=temp_dir / "wizard")

    with pytest.raises(FileNotFoundError) as exc_info:
        loader.load_flow('nonexistent')

    assert 'nonexistent' in str(exc_info.value)


def test_loader_invalid_yaml(temp_dir):
    """SpecLoader raises error for invalid YAML."""
    service_dir = temp_dir / "wizard" / "services" / "bad"
    service_dir.mkdir(parents=True)

    spec_file = service_dir / "spec.yaml"
    spec_file.write_text("invalid: yaml: content: [")

    loader = SpecLoader(base_path=temp_dir / "wizard")

    with pytest.raises(Exception):  # YAML parsing error
        loader.load_service_spec('bad')


def test_loader_missing_required_fields(temp_dir):
    """SpecLoader validates required fields are present."""
    service_dir = temp_dir / "wizard" / "services" / "incomplete"
    service_dir.mkdir(parents=True)

    # Missing 'service' field
    spec_content = """
version: "1.0"
description: Test
"""
    spec_file = service_dir / "spec.yaml"
    spec_file.write_text(spec_content)

    loader = SpecLoader(base_path=temp_dir / "wizard")

    with pytest.raises(Exception):  # Validation error
        loader.load_service_spec('incomplete')
