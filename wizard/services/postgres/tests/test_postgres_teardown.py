"""Tests for PostgreSQL teardown actions - RED phase."""

import pytest
import yaml
from pathlib import Path
from wizard.engine.runner import MockActionRunner


class TestTeardownSpec:
    """Tests for teardown-spec.yaml structure."""

    def test_teardown_spec_exists(self):
        """Teardown spec file should exist."""
        spec_path = Path(__file__).parent.parent / 'teardown-spec.yaml'
        assert spec_path.exists(), "teardown-spec.yaml should exist"

    def test_teardown_spec_loads_successfully(self):
        """Teardown spec should be valid YAML."""
        spec_path = Path(__file__).parent.parent / 'teardown-spec.yaml'
        with open(spec_path) as f:
            spec = yaml.safe_load(f)

        assert spec is not None
        assert 'service' in spec
        assert spec['service'] == 'postgres'
        assert 'steps' in spec
        assert isinstance(spec['steps'], list)

    def test_teardown_spec_has_required_steps(self):
        """Teardown spec should have all required steps."""
        spec_path = Path(__file__).parent.parent / 'teardown-spec.yaml'
        with open(spec_path) as f:
            spec = yaml.safe_load(f)

        step_ids = [step['id'] for step in spec['steps']]

        # Required steps for teardown (now with namespaced IDs)
        assert 'postgres_teardown_confirm' in step_ids
        assert 'stop_service' in step_ids
        assert 'postgres_remove_volumes' in step_ids
        assert 'remove_volumes_action' in step_ids
        assert 'postgres_remove_images' in step_ids
        assert 'remove_images_action' in step_ids
        assert 'clean_config' in step_ids

    def test_confirm_teardown_is_boolean(self):
        """Confirm teardown step should be boolean type."""
        spec_path = Path(__file__).parent.parent / 'teardown-spec.yaml'
        with open(spec_path) as f:
            spec = yaml.safe_load(f)

        confirm_step = next(s for s in spec['steps'] if s['id'] == 'postgres_teardown_confirm')
        assert confirm_step['type'] == 'boolean'
        assert 'prompt' in confirm_step

    def test_stop_service_is_action(self):
        """Stop service step should be action type."""
        spec_path = Path(__file__).parent.parent / 'teardown-spec.yaml'
        with open(spec_path) as f:
            spec = yaml.safe_load(f)

        stop_step = next(s for s in spec['steps'] if s['id'] == 'stop_service')
        assert stop_step['type'] == 'action'
        assert stop_step['action'] == 'postgres.teardown.stop_service'

    def test_remove_volumes_has_condition(self):
        """Remove volumes prompt should be conditional."""
        spec_path = Path(__file__).parent.parent / 'teardown-spec.yaml'
        with open(spec_path) as f:
            spec = yaml.safe_load(f)

        remove_volumes_step = next(s for s in spec['steps'] if s['id'] == 'postgres_remove_volumes')
        assert remove_volumes_step['type'] == 'boolean'
        assert 'prompt' in remove_volumes_step


class TestStopService:
    """Tests for stop_service action."""

    def test_stop_service_calls_docker_compose_stop(self):
        """Should call docker container remove command."""
        from wizard.services.postgres.teardown_actions import stop_service

        runner = MockActionRunner()
        ctx = {}

        stop_service(ctx, runner)

        # Verify runner.run_shell was called
        assert len(runner.calls) == 1
        call = runner.calls[0]
        assert call[0] == 'run_shell'

        # Verify command uses docker container remove
        command = call[1]
        assert 'docker' in command
        assert 'remove' in command

    def test_stop_service_no_context_required(self):
        """Should work with empty context."""
        from wizard.services.postgres.teardown_actions import stop_service

        runner = MockActionRunner()
        ctx = {}

        # Should not raise
        stop_service(ctx, runner)
        assert len(runner.calls) == 1


class TestRemoveVolumes:
    """Tests for remove_volumes action."""

    def test_remove_volumes_calls_docker_volume_rm(self):
        """Should call docker volume rm command."""
        from wizard.services.postgres.teardown_actions import remove_volumes

        runner = MockActionRunner()
        ctx = {}

        remove_volumes(ctx, runner)

        # Verify runner.run_shell was called
        assert len(runner.calls) == 1
        call = runner.calls[0]
        assert call[0] == 'run_shell'

        # Verify command includes docker volume rm
        command = call[1]
        assert 'docker' in command
        assert 'volume' in command
        assert 'rm' in command

    def test_remove_volumes_targets_postgres_volume(self):
        """Should target postgres data volume."""
        from wizard.services.postgres.teardown_actions import remove_volumes

        runner = MockActionRunner()
        ctx = {}

        remove_volumes(ctx, runner)

        call = runner.calls[0]
        command = call[1]
        # Command should mention postgres volume
        command_str = ' '.join(command)
        assert 'postgres' in command_str.lower()


class TestRemoveImages:
    """Tests for remove_images action."""

    def test_remove_images_calls_docker_rmi(self):
        """Should call docker rmi command."""
        from wizard.services.postgres.teardown_actions import remove_images

        runner = MockActionRunner()
        ctx = {
            'services.postgres.image': 'postgres:17.5-alpine'
        }

        remove_images(ctx, runner)

        # Verify runner.run_shell was called
        assert len(runner.calls) == 1
        call = runner.calls[0]
        assert call[0] == 'run_shell'

        # Verify command includes docker rmi
        command = call[1]
        assert 'docker' in command
        assert 'rmi' in command

    def test_remove_images_uses_context_image(self):
        """Should use image from context."""
        from wizard.services.postgres.teardown_actions import remove_images

        runner = MockActionRunner()
        ctx = {
            'services.postgres.image': 'postgres:17.5-alpine'
        }

        remove_images(ctx, runner)

        call = runner.calls[0]
        command = call[1]
        assert 'postgres:17.5-alpine' in command

    def test_remove_images_handles_missing_image(self):
        """Should use default image if context doesn't have one."""
        from wizard.services.postgres.teardown_actions import remove_images

        runner = MockActionRunner()
        ctx = {}

        remove_images(ctx, runner)

        call = runner.calls[0]
        command = call[1]
        # Should have some postgres image
        command_str = ' '.join(command)
        assert 'postgres' in command_str.lower()


class TestCleanConfig:
    """Tests for clean_config action."""

    def test_clean_config_calls_runner_save_config(self):
        """Should call runner.save_config to disable postgres."""
        from wizard.services.postgres.teardown_actions import clean_config

        runner = MockActionRunner()
        ctx = {}

        clean_config(ctx, runner)

        # Verify runner.save_config was called
        assert len(runner.calls) == 1
        call = runner.calls[0]
        assert call[0] == 'save_config'

        # Verify config structure
        config = call[1]
        assert 'services' in config
        assert 'postgres' in config['services']
        assert config['services']['postgres']['enabled'] is False

    def test_clean_config_preserves_other_settings(self):
        """Should only change enabled flag."""
        from wizard.services.postgres.teardown_actions import clean_config

        runner = MockActionRunner()
        ctx = {
            'services.postgres.image': 'postgres:17.5-alpine',
            'services.postgres.port': 5432
        }

        clean_config(ctx, runner)

        call = runner.calls[0]
        config = call[1]
        # Should preserve image and port
        assert config['services']['postgres']['image'] == 'postgres:17.5-alpine'
        assert config['services']['postgres']['port'] == 5432
        assert config['services']['postgres']['enabled'] is False


class TestActionSignatures:
    """Tests for action function signatures."""

    def test_all_actions_have_correct_signature(self):
        """All action functions should accept (ctx, runner)."""
        from wizard.services.postgres import teardown_actions
        import inspect

        actions = ['stop_service', 'remove_volumes', 'remove_images', 'clean_config']

        for action_name in actions:
            action = getattr(teardown_actions, action_name)
            sig = inspect.signature(action)
            params = list(sig.parameters.keys())

            assert len(params) == 2, f"{action_name} should have 2 parameters"
            assert params[0] == 'ctx', f"{action_name} first param should be 'ctx'"
            assert params[1] == 'runner', f"{action_name} second param should be 'runner'"

    def test_all_actions_have_type_hints(self):
        """All action functions should have type hints."""
        from wizard.services.postgres import teardown_actions
        import inspect

        actions = ['stop_service', 'remove_volumes', 'remove_images', 'clean_config']

        for action_name in actions:
            action = getattr(teardown_actions, action_name)
            sig = inspect.signature(action)

            # Check ctx type hint
            ctx_param = sig.parameters['ctx']
            assert ctx_param.annotation != inspect.Parameter.empty, \
                f"{action_name} ctx parameter should have type hint"

            # Check runner type hint (can be any type)
            runner_param = sig.parameters['runner']
            assert runner_param.annotation != inspect.Parameter.empty, \
                f"{action_name} runner parameter should have type hint"

            # Check return type hint
            assert sig.return_annotation == None or sig.return_annotation == type(None), \
                f"{action_name} should return None"
