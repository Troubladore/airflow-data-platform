"""Tests for Pydantic schema models."""

import pytest
from pydantic import ValidationError
from wizard.engine.schema import Step, ServiceSpec, Flow


def test_step_minimal_valid():
    """Step can be created with minimal required fields."""
    step = Step(
        id='test_step',
        type='string',
        prompt='Enter value:',
        state_key='test.value'
    )

    assert step.id == 'test_step'
    assert step.type == 'string'
    assert step.prompt == 'Enter value:'
    assert step.state_key == 'test.value'
    assert step.next is None
    assert step.validator is None
    assert step.action is None


def test_step_with_all_fields():
    """Step can be created with all optional fields."""
    step = Step(
        id='postgres_image',
        type='string',
        prompt='Image URL:',
        state_key='services.base_platform.postgres.image',
        default_value='postgres:17.5',
        default_from='services.base_platform.postgres.image',
        validator='postgres.validate_image_url',
        action='postgres.save_config',
        next='next_step'
    )

    assert step.default_value == 'postgres:17.5'
    assert step.default_from == 'services.base_platform.postgres.image'
    assert step.validator == 'postgres.validate_image_url'
    assert step.action == 'postgres.save_config'
    assert step.next == 'next_step'


def test_step_conditional_next():
    """Step can have conditional next based on when_changed/when_unchanged."""
    step = Step(
        id='test_step',
        type='string',
        prompt='Value:',
        state_key='test.value',
        next={
            'when_changed': 'step_a',
            'when_unchanged': 'step_b'
        }
    )

    assert isinstance(step.next, dict)
    assert step.next['when_changed'] == 'step_a'
    assert step.next['when_unchanged'] == 'step_b'


def test_step_requires_id():
    """Step must have an id."""
    with pytest.raises(ValidationError) as exc_info:
        Step(
            type='string',
            prompt='Value:',
            state_key='test.value'
        )

    assert 'id' in str(exc_info.value)


def test_step_requires_type():
    """Step must have a type."""
    with pytest.raises(ValidationError) as exc_info:
        Step(
            id='test',
            prompt='Value:',
            state_key='test.value'
        )

    assert 'type' in str(exc_info.value)


def test_service_spec_minimal():
    """ServiceSpec can be created with minimal fields."""
    spec = ServiceSpec(
        service='postgres',
        version='1.0',
        description='PostgreSQL service',
        requires=[],
        provides=['db.postgres'],
        steps=[
            Step(
                id='step1',
                type='string',
                prompt='Value:',
                state_key='test.value'
            )
        ]
    )

    assert spec.service == 'postgres'
    assert spec.version == '1.0'
    assert spec.requires == []
    assert spec.provides == ['db.postgres']
    assert len(spec.steps) == 1


def test_service_spec_with_dependencies():
    """ServiceSpec can declare dependencies."""
    spec = ServiceSpec(
        service='openmetadata',
        version='1.0',
        description='OpenMetadata service',
        requires=['db.postgres'],
        provides=['catalog.openmetadata'],
        steps=[]
    )

    assert spec.requires == ['db.postgres']
    assert spec.provides == ['catalog.openmetadata']


def test_flow_minimal():
    """Flow can be created with minimal fields."""
    flow = Flow(
        name='setup',
        version='1.0',
        description='Setup wizard',
        service_selection=[],
        targets=[]
    )

    assert flow.name == 'setup'
    assert flow.version == '1.0'
    assert flow.service_selection == []
    assert flow.targets == []


def test_flow_with_targets():
    """Flow can have service targets."""
    flow = Flow(
        name='setup',
        version='1.0',
        description='Setup wizard',
        service_selection=[],
        targets=[
            {'service': 'postgres', 'required': True},
            {'service': 'openmetadata', 'condition': 'services.openmetadata.enabled == true'}
        ]
    )

    assert len(flow.targets) == 2
    assert flow.targets[0]['service'] == 'postgres'
    assert flow.targets[0]['required'] is True
    assert flow.targets[1]['service'] == 'openmetadata'
