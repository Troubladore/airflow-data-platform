"""Tests for WizardEngine - step execution and state management."""

import pytest
import tempfile
from pathlib import Path
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner
from wizard.engine.schema import Step, ServiceSpec


@pytest.fixture
def mock_runner():
    """Create a mock runner for testing."""
    return MockActionRunner()


@pytest.fixture
def temp_wizard_dir():
    """Create temporary wizard directory structure."""
    with tempfile.TemporaryDirectory() as tmpdir:
        wizard_dir = Path(tmpdir) / "wizard"
        wizard_dir.mkdir()
        (wizard_dir / "services").mkdir()
        (wizard_dir / "flows").mkdir()
        yield wizard_dir


def test_engine_initializes_with_runner(mock_runner):
    """WizardEngine initializes with injected runner."""
    engine = WizardEngine(mock_runner)

    assert engine.runner is mock_runner
    assert engine.state == {}
    assert engine.validators == {}
    assert engine.actions == {}


def test_engine_execute_simple_step(mock_runner):
    """WizardEngine can execute a simple string step."""
    engine = WizardEngine(mock_runner)

    step = Step(
        id='test_input',
        type='string',
        prompt='Enter value:',
        state_key='test.value'
    )

    # Execute step with headless input
    result = engine._execute_step(step, headless_inputs={'test_input': 'myvalue'})

    assert engine.state['test.value'] == 'myvalue'
    assert result == 'myvalue'


def test_engine_execute_step_with_default(mock_runner):
    """WizardEngine uses default value when no input provided."""
    engine = WizardEngine(mock_runner)

    step = Step(
        id='test_input',
        type='string',
        prompt='Enter value:',
        state_key='test.value',
        default_value='default123'
    )

    # Execute with empty input (should use default)
    result = engine._execute_step(step, headless_inputs={'test_input': ''})

    assert engine.state['test.value'] == 'default123'
    assert result == 'default123'


def test_engine_execute_step_with_default_from_state(mock_runner):
    """WizardEngine can read default from existing state."""
    engine = WizardEngine(mock_runner)
    engine.state['existing.value'] = 'from_state'

    step = Step(
        id='test_input',
        type='string',
        prompt='Enter value:',
        state_key='test.value',
        default_from='existing.value'
    )

    # Execute with empty input (should use default from state)
    result = engine._execute_step(step, headless_inputs={'test_input': ''})

    assert engine.state['test.value'] == 'from_state'


def test_engine_execute_action_step(mock_runner):
    """WizardEngine executes action steps via runner."""
    engine = WizardEngine(mock_runner)
    engine.state['test.value'] = 'testvalue'

    # Register a mock action
    def test_action(ctx, runner):
        runner.save_config({'value': ctx.get('test.value')}, 'test.yaml')

    engine.actions['test.test_action'] = test_action

    step = Step(
        id='test_action_step',
        type='action',
        prompt='Running action...',
        action='test.test_action'
    )

    engine._execute_step(step, headless_inputs={})

    # Verify action was called via runner (filter out config loading calls)
    save_config_calls = [c for c in mock_runner.calls if c[0] == 'save_config']
    assert len(save_config_calls) == 1
    assert save_config_calls[0][0] == 'save_config'


def test_engine_execute_step_with_validator(mock_runner):
    """WizardEngine validates input using registered validator."""
    engine = WizardEngine(mock_runner)

    # Register a mock validator
    def test_validator(value, ctx):
        if not value.startswith('valid_'):
            raise ValueError("Value must start with 'valid_'")
        return value

    engine.validators['test.test_validator'] = test_validator

    step = Step(
        id='test_input',
        type='string',
        prompt='Enter value:',
        state_key='test.value',
        validator='test.test_validator'
    )

    # Valid input should work
    result = engine._execute_step(step, headless_inputs={'test_input': 'valid_value'})
    assert engine.state['test.value'] == 'valid_value'

    # Invalid input should raise error
    with pytest.raises(ValueError, match="must start with"):
        engine._execute_step(step, headless_inputs={'test_input': 'invalid'})


def test_engine_execute_service_basic(mock_runner, temp_wizard_dir):
    """WizardEngine can execute a basic service spec."""
    # Create a simple service spec
    service_spec = ServiceSpec(
        service='test_service',
        version='1.0',
        description='Test service',
        requires=[],
        provides=['test.capability'],
        steps=[
            Step(
                id='step1',
                type='string',
                prompt='Value:',
                state_key='test.step1'
            ),
            Step(
                id='step2',
                type='string',
                prompt='Value:',
                state_key='test.step2',
                next=None  # No next = end
            )
        ]
    )

    engine = WizardEngine(mock_runner, base_path=temp_wizard_dir)

    # Execute service with headless inputs
    engine._execute_service(
        service_spec,
        headless_inputs={
            'step1': 'value1',
            'step2': 'value2'
        }
    )

    assert engine.state['test.step1'] == 'value1'
    assert engine.state['test.step2'] == 'value2'


def test_engine_conditional_next(mock_runner):
    """WizardEngine handles conditional next based on when_changed/when_unchanged."""
    engine = WizardEngine(mock_runner)
    engine.state['test.value'] = 'original'

    step = Step(
        id='test_input',
        type='string',
        prompt='Enter value:',
        state_key='test.value',
        default_from='test.value',
        next={
            'when_changed': 'changed_path',
            'when_unchanged': 'unchanged_path'
        }
    )

    # When value changes
    next_step = engine._resolve_next(step, 'newvalue', 'original')
    assert next_step == 'changed_path'

    # When value stays same
    next_step = engine._resolve_next(step, 'original', 'original')
    assert next_step == 'unchanged_path'


def test_engine_headless_mode(mock_runner):
    """WizardEngine supports headless inputs for testing."""
    engine = WizardEngine(mock_runner)

    step = Step(
        id='user_input',
        type='string',
        prompt='Enter something:',
        state_key='user.input'
    )

    headless_inputs = {'user_input': 'automated_value'}

    result = engine._execute_step(step, headless_inputs=headless_inputs)

    assert result == 'automated_value'
    assert engine.state['user.input'] == 'automated_value'


def test_load_existing_state_handles_nested_config():
    """_load_existing_state should recursively flatten nested YAML config.

    When platform-config.yaml contains:
        services:
          base_platform:
            test_containers:
              postgres_test:
                image: alpine:latest
                prebuilt: false

    The state should include:
        services.base_platform.test_containers.postgres_test.image = "alpine:latest"
        services.base_platform.test_containers.postgres_test.prebuilt = False

    Not:
        services.base_platform.test_containers = {entire dict}
    """
    import yaml

    # Create a mock runner
    mock_runner = MockActionRunner()

    # Create the config file content
    config_content = {
        'services': {
            'base_platform': {
                'postgres': {
                    'enabled': True,
                    'image': 'postgres:17.5-alpine',
                    'auth_method': 'trust',
                    'password': None
                },
                'test_containers': {
                    'postgres_test': {
                        'image': 'alpine:latest',
                        'prebuilt': False
                    },
                    'sqlcmd_test': {
                        'image': 'alpine:latest',
                        'prebuilt': False
                    }
                }
            }
        }
    }

    # Set up the mock to return the config file content
    config_yaml = yaml.dump(config_content, default_flow_style=False)

    # Mock file_exists to return True for platform-config.yaml
    mock_runner.responses['file_exists'] = {'platform-config.yaml': True}

    # Mock the cat command to return the YAML content
    mock_runner.responses['run_shell'] = {
        tuple(['cat', 'platform-config.yaml']): {
            'stdout': config_yaml,
            'stderr': '',
            'returncode': 0
        }
    }

    # Create engine - this will call _load_existing_state
    engine = WizardEngine(mock_runner)

    # Verify nested config was flattened correctly
    assert engine.state.get('services.base_platform.test_containers.postgres_test.image') == 'alpine:latest'
    assert engine.state.get('services.base_platform.test_containers.postgres_test.prebuilt') is False
    assert engine.state.get('services.base_platform.test_containers.sqlcmd_test.image') == 'alpine:latest'
    assert engine.state.get('services.base_platform.test_containers.sqlcmd_test.prebuilt') is False

    # Verify it didn't create a dict entry
    assert 'services.base_platform.test_containers' not in engine.state
