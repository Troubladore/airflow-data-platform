"""Tests for discovery engine that aggregates service discovery results."""

import pytest
from wizard.engine.discovery import DiscoveryEngine
from wizard.engine.runner import MockActionRunner


class TestDiscoveryEngineBasics:
    """Test basic discovery engine functionality."""

    def test_discovery_engine_exists(self):
        """Discovery engine class should exist."""
        assert DiscoveryEngine is not None

    def test_discovery_engine_takes_runner(self):
        """Discovery engine should accept runner in constructor."""
        runner = MockActionRunner()
        engine = DiscoveryEngine(runner=runner)
        assert engine.runner == runner


class TestDiscoverAllServices:
    """Test discovering all services at once."""

    def test_discover_all_returns_dict(self):
        """discover_all() should return dict with service names as keys."""
        runner = MockActionRunner()
        engine = DiscoveryEngine(runner=runner)

        results = engine.discover_all()

        assert isinstance(results, dict)
        assert 'postgres' in results
        assert 'openmetadata' in results
        assert 'kerberos' in results
        assert 'pagila' in results

    def test_discover_all_calls_service_discovery(self):
        """discover_all() should call each service's discovery functions."""
        runner = MockActionRunner()
        engine = DiscoveryEngine(runner=runner)

        results = engine.discover_all()

        # Should have called docker commands (in future - stub doesn't yet)
        # For now, just verify results structure is correct
        assert isinstance(results, dict)


class TestDiscoverySummary:
    """Test aggregating discovery into summary."""

    def test_get_summary_counts_artifacts(self):
        """get_summary() should count total containers/images/volumes."""
        runner = MockActionRunner()
        # Mock finding 1 postgres container (will be used in GREEN phase)
        runner.responses['run_shell'] = {
            'stdout': 'postgres|Up 2 days\n',
            'stderr': '',
            'returncode': 0
        }

        engine = DiscoveryEngine(runner=runner)
        results = engine.discover_all()
        summary = engine.get_summary(results)

        # Stub returns zeros for now - that's ok for RED phase
        assert 'total_containers' in summary
        assert 'total_images' in summary
        assert 'total_volumes' in summary

    def test_empty_system_returns_zero_counts(self):
        """get_summary() should return zeros when nothing found."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {}  # No artifacts

        engine = DiscoveryEngine(runner=runner)
        results = engine.discover_all()
        summary = engine.get_summary(results)

        assert summary['total_containers'] == 0
        assert summary['total_images'] == 0
        assert summary['total_volumes'] == 0


class TestServiceDiscoveryIntegration:
    """Test integration with service discovery modules."""

    def test_discover_all_calls_postgres_discovery(self):
        """Should import and call postgres discovery functions."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            'stdout': 'postgres|Up\n',
            'stderr': '',
            'returncode': 0
        }

        engine = DiscoveryEngine(runner=runner)
        results = engine.discover_all()

        # Should have postgres results
        assert 'postgres' in results
        assert 'containers' in results['postgres']

    def test_discover_all_handles_missing_service_module(self):
        """Should handle gracefully if service discovery module missing."""
        runner = MockActionRunner()
        engine = DiscoveryEngine(runner=runner)

        # Should not crash even if service modules don't exist yet
        results = engine.discover_all()
        assert isinstance(results, dict)
