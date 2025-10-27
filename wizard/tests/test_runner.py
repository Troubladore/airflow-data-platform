"""Tests for ActionRunner interface in wizard engine."""

import pytest
import tempfile
import os
import yaml
from wizard.engine.runner import ActionRunner, RealActionRunner, MockActionRunner


class TestDisplayMethod:
    """Test display() method in ActionRunner implementations."""

    def test_real_runner_has_display_method(self):
        """RealActionRunner should have display() method."""
        runner = RealActionRunner()
        assert hasattr(runner, 'display')
        assert callable(runner.display)

    def test_mock_runner_has_display_method(self):
        """MockActionRunner should have display() method."""
        runner = MockActionRunner()
        assert hasattr(runner, 'display')
        assert callable(runner.display)

    def test_mock_runner_captures_display_calls(self):
        """MockActionRunner should record display() calls."""
        runner = MockActionRunner()

        runner.display("Test message")

        assert len(runner.calls) == 1
        assert runner.calls[0] == ('display', 'Test message')

    def test_mock_runner_captures_multiple_displays(self):
        """MockActionRunner should record multiple display calls."""
        runner = MockActionRunner()

        runner.display("Message 1")
        runner.display("Message 2")

        assert len(runner.calls) == 2
        assert runner.calls[0] == ('display', 'Message 1')
        assert runner.calls[1] == ('display', 'Message 2')


class TestGetInputMethod:
    """Test get_input() method in ActionRunner implementations."""

    def test_real_runner_has_get_input_method(self):
        """RealActionRunner should have get_input() method."""
        runner = RealActionRunner()
        assert hasattr(runner, 'get_input')
        assert callable(runner.get_input)

    def test_mock_runner_has_get_input_method(self):
        """MockActionRunner should have get_input() method."""
        runner = MockActionRunner()
        assert hasattr(runner, 'get_input')
        assert callable(runner.get_input)

    def test_mock_runner_captures_get_input_calls(self):
        """MockActionRunner should record get_input() calls."""
        runner = MockActionRunner()

        result = runner.get_input("Enter name:", "default")

        assert len(runner.calls) == 1
        assert runner.calls[0] == ('get_input', 'Enter name:', 'default')

    def test_mock_runner_returns_from_input_queue(self):
        """MockActionRunner should return values from input_queue."""
        runner = MockActionRunner()
        runner.input_queue = ['value1', 'value2']

        result1 = runner.get_input("Prompt 1:", None)
        result2 = runner.get_input("Prompt 2:", None)

        assert result1 == 'value1'
        assert result2 == 'value2'

    def test_mock_runner_returns_default_when_queue_empty(self):
        """MockActionRunner should return default if input_queue empty."""
        runner = MockActionRunner()
        runner.input_queue = []

        result = runner.get_input("Prompt:", "default_value")

        assert result == 'default_value'


class TestSaveConfigMethod:
    """Test save_config() method - deep merge and deletion logic."""

    def test_save_config_creates_new_file_when_none_exists(self):
        """Should create new config file when it doesn't exist."""
        runner = RealActionRunner()

        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = os.path.join(tmpdir, 'platform-config.yaml')

            config = {
                'services': {
                    'postgres': {
                        'enabled': True,
                        'image': 'postgres:17.5-alpine'
                    }
                }
            }

            runner.save_config(config, config_path)

            # Verify file was created
            assert os.path.exists(config_path)

            # Verify content
            with open(config_path, 'r') as f:
                saved_config = yaml.safe_load(f)

            assert saved_config == config

    def test_save_config_merges_with_existing_config(self):
        """Should deep merge with existing config, not replace."""
        runner = RealActionRunner()

        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = os.path.join(tmpdir, 'platform-config.yaml')

            # Create existing config with postgres
            existing_config = {
                'services': {
                    'postgres': {
                        'enabled': True,
                        'image': 'postgres:17.5-alpine',
                        'password': 'secret'
                    }
                }
            }

            with open(config_path, 'w') as f:
                yaml.dump(existing_config, f)

            # Save new config with kerberos
            new_config = {
                'services': {
                    'kerberos': {
                        'enabled': True,
                        'domain': 'EXAMPLE.COM'
                    }
                }
            }

            runner.save_config(new_config, config_path)

            # Verify both services are present (deep merge)
            with open(config_path, 'r') as f:
                saved_config = yaml.safe_load(f)

            assert 'postgres' in saved_config['services']
            assert 'kerberos' in saved_config['services']
            assert saved_config['services']['postgres']['enabled'] == True
            assert saved_config['services']['kerberos']['enabled'] == True

    def test_save_config_updates_existing_service(self):
        """Should update existing service config with new values."""
        runner = RealActionRunner()

        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = os.path.join(tmpdir, 'platform-config.yaml')

            # Create existing config with multiple services
            existing_config = {
                'services': {
                    'postgres': {
                        'enabled': True,
                        'image': 'postgres:17.5-alpine',
                        'password': 'secret'
                    },
                    'kerberos': {
                        'enabled': True,
                        'domain': 'EXAMPLE.COM'
                    }
                }
            }

            with open(config_path, 'w') as f:
                yaml.dump(existing_config, f)

            # Update postgres config (disable it)
            new_config = {
                'services': {
                    'postgres': {
                        'enabled': False
                    }
                }
            }

            runner.save_config(new_config, config_path)

            # Verify postgres was updated and file still exists (kerberos is enabled)
            with open(config_path, 'r') as f:
                saved_config = yaml.safe_load(f)

            assert saved_config['services']['postgres']['enabled'] == False
            # Old values should be preserved
            assert saved_config['services']['postgres']['image'] == 'postgres:17.5-alpine'
            # Kerberos should still be there and enabled
            assert saved_config['services']['kerberos']['enabled'] == True

    def test_save_config_deletes_file_when_all_services_disabled(self):
        """RED TEST: Should delete config file when all services are disabled."""
        runner = RealActionRunner()

        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = os.path.join(tmpdir, 'platform-config.yaml')

            # Create existing config with one enabled service
            existing_config = {
                'services': {
                    'postgres': {
                        'enabled': True,
                        'image': 'postgres:17.5-alpine'
                    }
                }
            }

            with open(config_path, 'w') as f:
                yaml.dump(existing_config, f)

            # Disable the service
            disable_config = {
                'services': {
                    'postgres': {
                        'enabled': False
                    }
                }
            }

            runner.save_config(disable_config, config_path)

            # File should be deleted when all services are disabled
            assert not os.path.exists(config_path), "Config file should be deleted when all services disabled"

    def test_save_config_deletes_file_when_multiple_services_all_disabled(self):
        """RED TEST: Should delete config file when multiple services are all disabled."""
        runner = RealActionRunner()

        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = os.path.join(tmpdir, 'platform-config.yaml')

            # Create existing config with multiple services
            existing_config = {
                'services': {
                    'postgres': {
                        'enabled': True,
                        'image': 'postgres:17.5-alpine'
                    },
                    'kerberos': {
                        'enabled': True,
                        'domain': 'EXAMPLE.COM'
                    }
                }
            }

            with open(config_path, 'w') as f:
                yaml.dump(existing_config, f)

            # Disable postgres
            runner.save_config({
                'services': {
                    'postgres': {
                        'enabled': False
                    }
                }
            }, config_path)

            # File should still exist (kerberos is enabled)
            assert os.path.exists(config_path)

            # Now disable kerberos too
            runner.save_config({
                'services': {
                    'kerberos': {
                        'enabled': False
                    }
                }
            }, config_path)

            # Now file should be deleted
            assert not os.path.exists(config_path), "Config file should be deleted when all services disabled"

    def test_save_config_keeps_file_when_at_least_one_service_enabled(self):
        """Should keep config file when at least one service is enabled."""
        runner = RealActionRunner()

        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = os.path.join(tmpdir, 'platform-config.yaml')

            # Create existing config with multiple services
            existing_config = {
                'services': {
                    'postgres': {
                        'enabled': True,
                        'image': 'postgres:17.5-alpine'
                    },
                    'kerberos': {
                        'enabled': True,
                        'domain': 'EXAMPLE.COM'
                    }
                }
            }

            with open(config_path, 'w') as f:
                yaml.dump(existing_config, f)

            # Disable only postgres
            runner.save_config({
                'services': {
                    'postgres': {
                        'enabled': False
                    }
                }
            }, config_path)

            # File should still exist (kerberos is still enabled)
            assert os.path.exists(config_path)

            # Verify content
            with open(config_path, 'r') as f:
                saved_config = yaml.safe_load(f)

            assert saved_config['services']['postgres']['enabled'] == False
            assert saved_config['services']['kerberos']['enabled'] == True
