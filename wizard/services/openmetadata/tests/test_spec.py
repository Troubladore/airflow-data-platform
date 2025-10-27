"""Tests for OpenMetadata spec.yaml - RED phase"""
import pytest
import yaml
from pathlib import Path


def test_spec_loads():
    """Loads spec.yaml without errors"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    assert spec_path.exists(), "spec.yaml must exist"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    assert spec is not None
    assert isinstance(spec, dict)


def test_spec_has_required_fields():
    """Spec contains required fields: service, version, description"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    assert "service" in spec
    assert spec["service"] == "openmetadata"
    assert "version" in spec
    assert "description" in spec


def test_spec_requires_postgres():
    """Spec declares dependency on postgres service"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    assert "requires" in spec, "spec must have 'requires' field for dependencies"
    assert isinstance(spec["requires"], list)
    assert "db.postgres" in spec["requires"], "OpenMetadata requires postgres database"


def test_spec_has_image_steps():
    """Spec includes steps for server_image and opensearch_image"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    assert "steps" in spec, "spec must have 'steps' field"
    assert isinstance(spec["steps"], list)

    # Find server_image step
    server_image_step = None
    opensearch_image_step = None

    for step in spec["steps"]:
        if step.get("id") == "server_image":
            server_image_step = step
        elif step.get("id") == "opensearch_image":
            opensearch_image_step = step

    assert server_image_step is not None, "Must have server_image step"
    assert opensearch_image_step is not None, "Must have opensearch_image step"


def test_spec_server_image_step_structure():
    """Server image step has correct structure and defaults"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    server_image_step = next(
        (s for s in spec["steps"] if s.get("id") == "server_image"),
        None
    )

    assert server_image_step["type"] == "string"
    assert server_image_step["prompt"] is not None
    assert "default_value" in server_image_step
    # Default should be a valid OpenMetadata server image
    assert "openmetadata/server" in server_image_step["default_value"].lower()


def test_spec_opensearch_image_step_structure():
    """OpenSearch image step has correct structure and defaults"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    opensearch_image_step = next(
        (s for s in spec["steps"] if s.get("id") == "opensearch_image"),
        None
    )

    assert opensearch_image_step["type"] == "string"
    assert opensearch_image_step["prompt"] is not None
    assert "default_value" in opensearch_image_step
    # Default should be a valid OpenSearch image
    assert "opensearch" in opensearch_image_step["default_value"].lower()


def test_spec_has_port_step():
    """Spec includes port configuration step"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    port_step = next(
        (s for s in spec["steps"] if s.get("id") == "port"),
        None
    )

    assert port_step is not None, "Must have port configuration step"
    assert port_step["type"] == "integer"
    assert port_step["default_value"] == 8585, "Default port should be 8585"


def test_spec_has_use_prebuilt_step():
    """Spec includes use_prebuilt flag step"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    prebuilt_step = next(
        (s for s in spec["steps"] if s.get("id") == "use_prebuilt"),
        None
    )

    assert prebuilt_step is not None, "Must have use_prebuilt step"
    assert prebuilt_step["type"] == "boolean"
    assert prebuilt_step["default_value"] is True, "Default should be True (use prebuilt)"


def test_spec_steps_have_validators():
    """Image and port steps reference validator functions"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    server_image_step = next(
        (s for s in spec["steps"] if s.get("id") == "server_image"),
        None
    )
    opensearch_image_step = next(
        (s for s in spec["steps"] if s.get("id") == "opensearch_image"),
        None
    )
    port_step = next(
        (s for s in spec["steps"] if s.get("id") == "port"),
        None
    )

    assert "validator" in server_image_step
    assert server_image_step["validator"] == "openmetadata.validate_image_url"

    assert "validator" in opensearch_image_step
    assert opensearch_image_step["validator"] == "openmetadata.validate_image_url"

    assert "validator" in port_step
    assert port_step["validator"] == "openmetadata.validate_port"


def test_spec_has_actions():
    """Spec defines actions for setup"""
    spec_path = Path(__file__).parent.parent / "spec.yaml"

    with open(spec_path) as f:
        spec = yaml.safe_load(f)

    # Actions are now defined as action steps in the steps list
    action_steps = [s for s in spec["steps"] if s.get("type") == "action"]
    assert len(action_steps) >= 2, "Must have at least 2 action steps"

    # Check for save_config and start_service actions
    action_names = [s.get("action") for s in action_steps]
    assert "openmetadata.save_config" in action_names
    assert "openmetadata.start_service" in action_names
