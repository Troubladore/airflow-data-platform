"""Test that start_service respects prebuilt images - RED phase for TDD."""

import pytest
from wizard.services.kerberos.actions import start_service


class MockActionRunner:
    """Mock runner to capture commands."""
    def __init__(self):
        self.commands = []
        self.displays = []
        self.mock_responses = {}

    def display(self, text):
        self.displays.append(text)

    def run_shell(self, cmd, **kwargs):
        self.commands.append(cmd)
        # Return mock responses for specific commands
        if ' '.join(cmd) in self.mock_responses:
            return self.mock_responses[' '.join(cmd)]
        # Default responses
        if 'echo $USERDNSDOMAIN' in ' '.join(cmd):
            return {'stdout': '', 'returncode': 0}  # Not in domain
        if 'command -v powershell.exe' in ' '.join(cmd):
            return {'returncode': 1}  # No PowerShell
        if 'docker ps' in ' '.join(cmd):
            return {'stdout': '', 'returncode': 0}  # No existing container
        if 'docker network ls' in ' '.join(cmd):
            return {'stdout': '', 'returncode': 0}  # Network doesn't exist
        if 'docker network create' in ' '.join(cmd):
            return {'returncode': 0}  # Network creation succeeds
        if 'docker volume create' in ' '.join(cmd):
            return {'returncode': 0}  # Volume creation succeeds
        if 'docker run' in ' '.join(cmd):
            return {'returncode': 0}  # Container starts
        if 'docker exec' in ' '.join(cmd):
            return {'returncode': 0}  # Package install succeeds
        return {'returncode': 0}


class TestStartServicePrebuilt:
    """Test that start_service respects prebuilt mode for corporate images."""

    def test_prebuilt_mode_uses_corporate_image(self):
        """Should use corporate image without modification when use_prebuilt is True."""
        # Given: A corporate prebuilt Kerberos image
        ctx = {
            'services.kerberos.image': 'mycorp.jfrog.io/docker-mirror/kerberos-base:latest',
            'services.kerberos.use_prebuilt': True,
            'services.kerberos.domain': 'CORP.EXAMPLE.COM'
        }
        runner = MockActionRunner()

        # When: Starting the service (in non-domain environment)
        start_service(ctx, runner)

        # Then: Should use the corporate image, not ubuntu:22.04
        docker_run_commands = [cmd for cmd in runner.commands if cmd[0] == 'docker' and cmd[1] == 'run']
        assert len(docker_run_commands) > 0, "Should have started a container"

        # The docker run command should use the corporate image
        docker_run = docker_run_commands[0]
        # The image comes right before 'sleep'
        image_index = docker_run.index('sleep') - 1
        image_used = docker_run[image_index]
        assert image_used == 'mycorp.jfrog.io/docker-mirror/kerberos-base:latest'
        assert image_used != 'ubuntu:22.04'

    def test_prebuilt_mode_skips_package_installation(self):
        """Should skip package installation when using prebuilt image."""
        # Given: A prebuilt Kerberos image
        ctx = {
            'services.kerberos.image': 'mycorp.jfrog.io/docker-mirror/kerberos-base:latest',
            'services.kerberos.use_prebuilt': True,
            'services.kerberos.domain': 'CORP.EXAMPLE.COM'
        }
        runner = MockActionRunner()

        # When: Starting the service
        start_service(ctx, runner)

        # Then: Should NOT attempt to install Kerberos packages
        docker_exec_commands = [cmd for cmd in runner.commands if cmd[0] == 'docker' and cmd[1] == 'exec']
        apt_install_commands = [cmd for cmd in docker_exec_commands if 'apt-get install' in ' '.join(cmd)]
        assert len(apt_install_commands) == 0, "Should not install packages in prebuilt image"

    def test_layered_mode_uses_ubuntu_and_installs_packages(self):
        """Should use ubuntu:22.04 and install packages when use_prebuilt is False."""
        # Given: Layered mode (not prebuilt)
        ctx = {
            'services.kerberos.use_prebuilt': False,
            'services.kerberos.domain': 'TEST.LOCAL'
        }
        runner = MockActionRunner()

        # When: Starting the service
        start_service(ctx, runner)

        # Then: Should use ubuntu:22.04
        docker_run_commands = [cmd for cmd in runner.commands if cmd[0] == 'docker' and cmd[1] == 'run']
        assert len(docker_run_commands) > 0
        docker_run = docker_run_commands[0]
        # The image comes right before 'sleep'
        image_index = docker_run.index('sleep') - 1
        image_used = docker_run[image_index]
        assert image_used == 'ubuntu:22.04'

        # And should install packages
        docker_exec_commands = [cmd for cmd in runner.commands if cmd[0] == 'docker' and cmd[1] == 'exec']
        apt_install_commands = [cmd for cmd in docker_exec_commands if 'apt-get install' in ' '.join(cmd)]
        assert len(apt_install_commands) > 0, "Should install packages in layered mode"