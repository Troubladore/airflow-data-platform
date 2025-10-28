"""Test that pull_image handles local corporate images correctly."""

import pytest
from wizard.services.postgres.actions import pull_image


class MockRunner:
    """Mock runner to capture commands."""
    def __init__(self):
        self.commands = []
        self.displays = []
        self.mock_responses = {}

    def display(self, text):
        self.displays.append(text)

    def run_shell(self, cmd, **kwargs):
        self.commands.append(cmd)
        # Join command for lookup
        cmd_str = ' '.join(cmd) if isinstance(cmd, list) else cmd

        if cmd_str in self.mock_responses:
            return self.mock_responses[cmd_str]

        # Default responses
        if 'docker' in cmd and 'inspect' in cmd:
            # Image inspection result
            return self.mock_responses.get('inspect', {'returncode': 0})
        if 'docker' in cmd and 'pull' in cmd:
            # Pull result
            return self.mock_responses.get('pull', {'returncode': 0})

        return {'returncode': 0}


class TestPullImageLocal:
    """Test that pull_image handles local images correctly."""

    def test_corporate_image_exists_locally_skip_pull(self):
        """Should skip pull when corporate image exists locally."""
        # Given: A corporate image that exists locally
        ctx = {
            'services.postgres.image': 'mycorp.jfrog.io/docker-mirror/postgres/17.5:2025.10.01',
            'services.postgres.prebuilt': False
        }
        runner = MockRunner()
        # Mock that image exists locally
        runner.mock_responses['docker image inspect mycorp.jfrog.io/docker-mirror/postgres/17.5:2025.10.01'] = {
            'returncode': 0  # Image exists
        }

        # When: Pulling the image
        pull_image(ctx, runner)

        # Then: Should check if image exists but NOT pull
        inspect_commands = [cmd for cmd in runner.commands if 'inspect' in cmd]
        pull_commands = [cmd for cmd in runner.commands if 'pull' in cmd]

        assert len(inspect_commands) == 1, "Should check if image exists"
        assert len(pull_commands) == 0, "Should NOT pull when image exists locally"
        assert "Image already exists locally" in ' '.join(runner.displays)

    def test_corporate_image_not_local_attempts_pull(self):
        """Should attempt pull when corporate image doesn't exist locally."""
        # Given: A corporate image that doesn't exist locally
        ctx = {
            'services.postgres.image': 'mycorp.jfrog.io/docker-mirror/postgres/17.5:2025.10.01',
            'services.postgres.prebuilt': False
        }
        runner = MockRunner()
        # Mock that image doesn't exist locally
        runner.mock_responses['docker image inspect mycorp.jfrog.io/docker-mirror/postgres/17.5:2025.10.01'] = {
            'returncode': 1  # Image doesn't exist
        }
        # Mock that pull fails (expected for fake registry)
        runner.mock_responses['pull'] = {'returncode': 1, 'stderr': 'no such host'}

        # When: Pulling the image
        pull_image(ctx, runner)

        # Then: Should check existence and attempt pull
        inspect_commands = [cmd for cmd in runner.commands if 'inspect' in cmd]
        pull_commands = [cmd for cmd in runner.commands if 'pull' in cmd]

        assert len(inspect_commands) == 1, "Should check if image exists"
        assert len(pull_commands) == 1, "Should attempt pull when not local"
        assert "Failed to pull image" in ' '.join(runner.displays)

    def test_dockerhub_image_always_pulls(self):
        """Should always pull Docker Hub images to get latest."""
        # Given: A Docker Hub image
        ctx = {
            'services.postgres.image': 'postgres:17.5-alpine',
            'services.postgres.prebuilt': False
        }
        runner = MockRunner()

        # When: Pulling the image
        pull_image(ctx, runner)

        # Then: Should pull without checking local existence
        inspect_commands = [cmd for cmd in runner.commands if 'inspect' in cmd]
        pull_commands = [cmd for cmd in runner.commands if 'pull' in cmd]

        assert len(inspect_commands) == 0, "Should NOT check Docker Hub images locally"
        assert len(pull_commands) == 1, "Should always pull Docker Hub images"

    def test_prebuilt_local_image_shows_correct_message(self):
        """Should show prebuilt message when using local prebuilt image."""
        # Given: A prebuilt corporate image that exists locally
        ctx = {
            'services.postgres.image': 'mycorp.jfrog.io/docker-mirror/postgres/17.5:2025.10.01',
            'services.postgres.prebuilt': True
        }
        runner = MockRunner()
        runner.mock_responses['docker image inspect mycorp.jfrog.io/docker-mirror/postgres/17.5:2025.10.01'] = {
            'returncode': 0  # Image exists
        }

        # When: Pulling the image
        pull_image(ctx, runner)

        # Then: Should show prebuilt message
        assert "Prebuilt image already exists locally" in ' '.join(runner.displays)
        assert len([cmd for cmd in runner.commands if 'pull' in cmd]) == 0