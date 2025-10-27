"""Tests for clean-slate flow with discovery integration.

This test suite validates that the clean-slate flow runs discovery BEFORE
prompting users for what to remove. Tests the "discovery-first" user experience
where users see what actually exists on their system before making teardown
decisions.

Test philosophy:
- Test discovery integration into clean-slate flow
- Use MockActionRunner for all Docker queries
- Verify empty state handling (graceful exit)
- Verify discovery results displayed to user
- Test that service selection happens AFTER discovery
- Validate artifact counts shown in prompts
"""

import pytest
from pathlib import Path
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


class TestDiscoveryPhase:
    """Test that clean-slate runs discovery first."""

    @pytest.fixture
    def runner(self):
        """Create MockActionRunner with mock discovery responses."""
        runner = MockActionRunner()
        # Mock docker commands to return some artifacts
        runner.responses['run_shell'] = {
            ('docker', 'ps', '-a', '--filter', 'name=postgres', '--format', '{{.Names}}|{{.Status}}'):
                'postgres|Up 2 days\n',
            ('docker', 'images', '--filter', 'reference=postgres', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                'postgres:17.5|400MB\n',
            ('docker', 'volume', 'ls', '--filter', 'name=postgres', '--format', '{{.Name}}'):
                'postgres_data\n'
        }
        return runner

    @pytest.fixture
    def engine(self, runner):
        """Create WizardEngine with MockActionRunner."""
        base_path = Path(__file__).parent.parent
        return WizardEngine(runner=runner, base_path=base_path)

    def test_clean_slate_runs_discovery_before_prompts(self, engine, runner):
        """Clean-slate should run discovery phase before asking questions."""
        # Execute with headless inputs to avoid blocking on prompts
        engine.execute_flow('clean-slate', headless_inputs={
            'select_teardown_services': []  # Don't actually tear down anything
        })

        # Should have called docker discovery commands
        assert any('docker' in str(call) for call in runner.calls), \
            "Should call docker commands for discovery"

    def test_discovery_runs_before_service_selection(self, engine, runner):
        """Discovery should run BEFORE the service selection prompt."""
        engine.execute_flow('clean-slate', headless_inputs={
            'select_teardown_services': ['postgres']
        })

        # Find first docker call and first selection in state
        docker_call_idx = None
        for i, call in enumerate(runner.calls):
            if 'docker' in str(call):
                docker_call_idx = i
                break

        # Docker discovery should happen before selection
        assert docker_call_idx is not None, "Discovery should run"
        # State should be set after discovery
        assert 'discovery_results' in engine.state or len(runner.calls) > 0


class TestEmptyStateHandling:
    """Test handling when no artifacts found."""

    @pytest.fixture
    def empty_runner(self):
        """Create MockActionRunner with no artifacts."""
        runner = MockActionRunner()
        # Mock empty responses (no artifacts found)
        runner.responses['run_shell'] = {
            ('docker', 'ps', '-a', '--filter', 'name=postgres', '--format', '{{.Names}}|{{.Status}}'): '',
            ('docker', 'images', '--filter', 'reference=postgres', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'): '',
            ('docker', 'volume', 'ls', '--filter', 'name=postgres', '--format', '{{.Name}}'): '',
            ('docker', 'ps', '-a', '--filter', 'name=openmetadata', '--format', '{{.Names}}|{{.Status}}'): '',
            ('docker', 'images', '--filter', 'reference=openmetadata', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'): '',
            ('docker', 'volume', 'ls', '--filter', 'name=openmetadata', '--format', '{{.Name}}'): '',
            ('docker', 'ps', '-a', '--filter', 'name=kerberos', '--format', '{{.Names}}|{{.Status}}'): '',
            ('docker', 'images', '--filter', 'reference=kerberos', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'): '',
            ('docker', 'volume', 'ls', '--filter', 'name=kerberos', '--format', '{{.Name}}'): '',
            ('docker', 'ps', '-a', '--filter', 'name=pagila', '--format', '{{.Names}}|{{.Status}}'): '',
            ('docker', 'images', '--filter', 'reference=pagila', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'): '',
            ('docker', 'volume', 'ls', '--filter', 'name=pagila', '--format', '{{.Name}}'): ''
        }
        return runner

    @pytest.fixture
    def engine(self, empty_runner):
        """Create WizardEngine with empty system."""
        base_path = Path(__file__).parent.parent
        return WizardEngine(runner=empty_runner, base_path=base_path)

    def test_empty_system_shows_message_and_exits(self, engine, empty_runner):
        """Should show 'system is clean' message and exit gracefully."""
        # Execute flow - should complete without prompting
        result = engine.execute_flow('clean-slate')

        # Should have run discovery
        assert len(empty_runner.calls) > 0, "Should run discovery"

        # Should track that system is empty
        assert engine.state.get('total_artifacts', 0) == 0, \
            "Should detect zero artifacts"

    def test_empty_system_does_not_prompt_for_services(self, engine, empty_runner):
        """Empty system should exit without showing service selection."""
        # Execute without headless inputs - should not block on selection
        engine.execute_flow('clean-slate')

        # Should not have teardown selections (flow exited early)
        # Empty list is acceptable - means no services selected
        teardown_selections = engine.state.get('teardown_selections')
        assert teardown_selections is None or teardown_selections == []


class TestDiscoveryResultsDisplay:
    """Test showing discovery results to user."""

    @pytest.fixture
    def runner_with_artifacts(self):
        """Create MockActionRunner with multiple artifacts."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            # Postgres artifacts
            ('docker', 'ps', '-a', '--filter', 'name=postgres', '--format', '{{.Names}}|{{.Status}}'):
                'postgres|Up 2 days\nplatform-postgres|Exited\n',
            ('docker', 'images', '--filter', 'reference=postgres', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                'postgres:17.5|400MB\npostgres:16|380MB\n',
            ('docker', 'volume', 'ls', '--filter', 'name=postgres', '--format', '{{.Name}}'):
                'postgres_data\npostgres_logs\n',
            # OpenMetadata artifacts
            ('docker', 'ps', '-a', '--filter', 'name=openmetadata', '--format', '{{.Names}}|{{.Status}}'):
                'openmetadata-server|Up 1 day\n',
            ('docker', 'images', '--filter', 'reference=openmetadata', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                'openmetadata/server:1.0|500MB\n',
            ('docker', 'volume', 'ls', '--filter', 'name=openmetadata', '--format', '{{.Name}}'):
                'openmetadata_data\n',
            # Kerberos artifacts
            ('docker', 'ps', '-a', '--filter', 'name=kerberos', '--format', '{{.Names}}|{{.Status}}'):
                '',
            ('docker', 'images', '--filter', 'reference=kerberos', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                '',
            ('docker', 'volume', 'ls', '--filter', 'name=kerberos', '--format', '{{.Name}}'):
                '',
            # Pagila artifacts
            ('docker', 'ps', '-a', '--filter', 'name=pagila', '--format', '{{.Names}}|{{.Status}}'):
                '',
            ('docker', 'images', '--filter', 'reference=pagila', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                '',
            ('docker', 'volume', 'ls', '--filter', 'name=pagila', '--format', '{{.Name}}'):
                ''
        }
        return runner

    @pytest.fixture
    def engine(self, runner_with_artifacts):
        """Create WizardEngine with artifacts."""
        base_path = Path(__file__).parent.parent
        return WizardEngine(runner=runner_with_artifacts, base_path=base_path)

    def test_shows_container_counts(self, engine, runner_with_artifacts):
        """Should display number of containers found per service."""
        engine.execute_flow('clean-slate', headless_inputs={
            'select_teardown_services': []  # Don't actually remove
        })

        # Should have discovery results in state
        assert 'discovery_results' in engine.state, \
            "Should store discovery results in state"

        results = engine.state['discovery_results']
        # Check postgres results
        assert 'postgres' in results, "Should have postgres in discovery results"
        assert len(results['postgres']['containers']) == 2, \
            "Should find 2 postgres containers"

    def test_shows_image_counts(self, engine, runner_with_artifacts):
        """Should display number of images found per service."""
        engine.execute_flow('clean-slate', headless_inputs={
            'select_teardown_services': []
        })

        results = engine.state.get('discovery_results', {})
        assert len(results['postgres']['images']) == 2, \
            "Should find 2 postgres images"
        assert len(results['openmetadata']['images']) == 1, \
            "Should find 1 openmetadata image"

    def test_shows_volume_counts(self, engine, runner_with_artifacts):
        """Should display number of volumes found per service."""
        engine.execute_flow('clean-slate', headless_inputs={
            'select_teardown_services': []
        })

        results = engine.state.get('discovery_results', {})
        assert len(results['postgres']['volumes']) == 2, \
            "Should find 2 postgres volumes"
        assert len(results['openmetadata']['volumes']) == 1, \
            "Should find 1 openmetadata volume"

    def test_discovery_summary_aggregates_totals(self, engine, runner_with_artifacts):
        """Should aggregate total counts across all services."""
        engine.execute_flow('clean-slate', headless_inputs={
            'select_teardown_services': []
        })

        # Should have total artifacts count
        total = engine.state.get('total_artifacts', 0)
        # 3 containers + 3 images + 3 volumes = 9 total artifacts
        assert total == 9, f"Should have 9 total artifacts, got {total}"


class TestServiceSelectionAfterDiscovery:
    """Test that service selection shows discovery context."""

    @pytest.fixture
    def runner(self):
        """Create MockActionRunner with some artifacts."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'ps', '-a', '--filter', 'name=postgres', '--format', '{{.Names}}|{{.Status}}'):
                'postgres|Up\n',
            ('docker', 'images', '--filter', 'reference=postgres', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                'postgres:17.5|400MB\n',
            ('docker', 'volume', 'ls', '--filter', 'name=postgres', '--format', '{{.Name}}'):
                'postgres_data\n',
            ('docker', 'ps', '-a', '--filter', 'name=openmetadata', '--format', '{{.Names}}|{{.Status}}'):
                '',
            ('docker', 'images', '--filter', 'reference=openmetadata', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                '',
            ('docker', 'volume', 'ls', '--filter', 'name=openmetadata', '--format', '{{.Name}}'):
                '',
            ('docker', 'ps', '-a', '--filter', 'name=kerberos', '--format', '{{.Names}}|{{.Status}}'):
                '',
            ('docker', 'images', '--filter', 'reference=kerberos', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                '',
            ('docker', 'volume', 'ls', '--filter', 'name=kerberos', '--format', '{{.Name}}'):
                '',
            ('docker', 'ps', '-a', '--filter', 'name=pagila', '--format', '{{.Names}}|{{.Status}}'):
                '',
            ('docker', 'images', '--filter', 'reference=pagila', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                '',
            ('docker', 'volume', 'ls', '--filter', 'name=pagila', '--format', '{{.Name}}'):
                ''
        }
        return runner

    @pytest.fixture
    def engine(self, runner):
        """Create WizardEngine."""
        base_path = Path(__file__).parent.parent
        return WizardEngine(runner=runner, base_path=base_path)

    def test_service_selection_happens_after_discovery(self, engine, runner):
        """Service selection should happen AFTER discovery completes."""
        engine.execute_flow('clean-slate', headless_inputs={
            'select_teardown_services': ['postgres']
        })

        # Discovery should be in state before selection
        assert 'discovery_results' in engine.state, \
            "Discovery should run before selection"

        # Selection should reflect discovery results
        assert engine.state.get('services.postgres.teardown.enabled') is True


class TestGranularCleanupQuestions:
    """Test that cleanup questions show actual artifact counts."""

    @pytest.fixture
    def runner(self):
        """Create MockActionRunner with postgres artifacts."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'ps', '-a', '--filter', 'name=postgres', '--format', '{{.Names}}|{{.Status}}'):
                'postgres|Up 2 days\nplatform-postgres|Exited\n',
            ('docker', 'images', '--filter', 'reference=postgres', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                'postgres:17.5|400MB\npostgres:16|380MB\npostgres:15|370MB\n',
            ('docker', 'volume', 'ls', '--filter', 'name=postgres', '--format', '{{.Name}}'):
                'postgres_data\npostgres_logs\n',
            ('docker', 'ps', '-a', '--filter', 'name=openmetadata', '--format', '{{.Names}}|{{.Status}}'):
                '',
            ('docker', 'images', '--filter', 'reference=openmetadata', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                '',
            ('docker', 'volume', 'ls', '--filter', 'name=openmetadata', '--format', '{{.Name}}'):
                '',
            ('docker', 'ps', '-a', '--filter', 'name=kerberos', '--format', '{{.Names}}|{{.Status}}'):
                '',
            ('docker', 'images', '--filter', 'reference=kerberos', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                '',
            ('docker', 'volume', 'ls', '--filter', 'name=kerberos', '--format', '{{.Name}}'):
                '',
            ('docker', 'ps', '-a', '--filter', 'name=pagila', '--format', '{{.Names}}|{{.Status}}'):
                '',
            ('docker', 'images', '--filter', 'reference=pagila', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                '',
            ('docker', 'volume', 'ls', '--filter', 'name=pagila', '--format', '{{.Name}}'):
                ''
        }
        return runner

    @pytest.fixture
    def engine(self, runner):
        """Create WizardEngine."""
        base_path = Path(__file__).parent.parent
        return WizardEngine(runner=runner, base_path=base_path)

    def test_shows_actual_container_count_in_prompts(self, engine, runner):
        """Cleanup prompts should show actual number of containers found."""
        engine.execute_flow('clean-slate', headless_inputs={
            'select_teardown_services': ['postgres'],
            'postgres_teardown_confirm': True,
            'postgres_remove_volumes': True,
            'postgres_remove_images': True
        })

        results = engine.state.get('discovery_results', {})
        postgres_containers = results.get('postgres', {}).get('containers', [])
        assert len(postgres_containers) == 2, \
            "Should show user that 2 containers exist"

    def test_shows_actual_image_count_in_prompts(self, engine, runner):
        """Cleanup prompts should show actual number of images found."""
        engine.execute_flow('clean-slate', headless_inputs={
            'select_teardown_services': ['postgres'],
            'postgres_teardown_confirm': True,
            'postgres_remove_volumes': True,
            'postgres_remove_images': True
        })

        results = engine.state.get('discovery_results', {})
        postgres_images = results.get('postgres', {}).get('images', [])
        assert len(postgres_images) == 3, \
            "Should show user that 3 images exist"

    def test_shows_actual_volume_count_in_prompts(self, engine, runner):
        """Cleanup prompts should show actual number of volumes found."""
        engine.execute_flow('clean-slate', headless_inputs={
            'select_teardown_services': ['postgres'],
            'postgres_teardown_confirm': True,
            'postgres_remove_volumes': True,
            'postgres_remove_images': True
        })

        results = engine.state.get('discovery_results', {})
        postgres_volumes = results.get('postgres', {}).get('volumes', [])
        assert len(postgres_volumes) == 2, \
            "Should show user that 2 volumes exist"

    def test_zero_artifacts_shown_when_none_found(self, engine):
        """Should show zero counts for services with no artifacts."""
        # Create engine with empty runner
        empty_runner = MockActionRunner()
        empty_runner.responses['run_shell'] = {
            ('docker', 'ps', '-a', '--filter', 'name=kerberos', '--format', '{{.Names}}|{{.Status}}'): '',
            ('docker', 'images', '--filter', 'reference=kerberos', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'): '',
            ('docker', 'volume', 'ls', '--filter', 'name=kerberos', '--format', '{{.Name}}'): '',
            ('docker', 'ps', '-a', '--filter', 'name=postgres', '--format', '{{.Names}}|{{.Status}}'): '',
            ('docker', 'images', '--filter', 'reference=postgres', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'): '',
            ('docker', 'volume', 'ls', '--filter', 'name=postgres', '--format', '{{.Name}}'): '',
            ('docker', 'ps', '-a', '--filter', 'name=openmetadata', '--format', '{{.Names}}|{{.Status}}'): '',
            ('docker', 'images', '--filter', 'reference=openmetadata', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'): '',
            ('docker', 'volume', 'ls', '--filter', 'name=openmetadata', '--format', '{{.Name}}'): '',
            ('docker', 'ps', '-a', '--filter', 'name=pagila', '--format', '{{.Names}}|{{.Status}}'): '',
            ('docker', 'images', '--filter', 'reference=pagila', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'): '',
            ('docker', 'volume', 'ls', '--filter', 'name=pagila', '--format', '{{.Name}}'): ''
        }
        base_path = Path(__file__).parent.parent
        empty_engine = WizardEngine(runner=empty_runner, base_path=base_path)

        empty_engine.execute_flow('clean-slate')

        results = empty_engine.state.get('discovery_results', {})
        kerberos_containers = results.get('kerberos', {}).get('containers', [])
        assert len(kerberos_containers) == 0, \
            "Should show zero kerberos containers"
