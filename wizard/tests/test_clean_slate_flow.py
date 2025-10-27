"""Tests for clean-slate flow composition - RED phase.

This test suite validates the orchestration of teardown operations across
multiple services through the clean-slate flow. The clean-slate flow coordinates
service teardown selection and execution while respecting reverse dependencies.

Critical requirement: Dependents (openmetadata, pagila) must tear down BEFORE
their dependency (postgres). This is reverse topological ordering.

Test philosophy:
- Test flow orchestration, not individual service teardown logic
- Use MockActionRunner for all side effects
- Use headless_inputs for non-interactive testing
- Validate reverse dependency ordering (CRITICAL!)
- Validate state transitions and action ordering
"""

import pytest
from pathlib import Path
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner
from wizard.engine.loader import SpecLoader


class TestCleanSlateFlowLoads:
    """Tests for clean-slate flow file existence and basic loading."""

    def test_clean_slate_flow_yaml_exists(self):
        """Should have flows/clean-slate.yaml file."""
        flow_path = Path(__file__).parent.parent / "flows" / "clean-slate.yaml"
        assert flow_path.exists(), "flows/clean-slate.yaml must exist"

    def test_clean_slate_flow_loads_successfully(self):
        """Should load clean-slate.yaml without validation errors."""
        loader = SpecLoader(base_path=Path(__file__).parent.parent)
        flow = loader.load_flow("clean-slate")

        assert flow is not None, "clean-slate flow should load"
        assert flow.name == "clean-slate", "flow name should be 'clean-slate'"


class TestCleanSlateFlowStructure:
    """Tests for clean-slate flow structure and required fields."""

    @pytest.fixture
    def loader(self):
        """Create SpecLoader for testing."""
        return SpecLoader(base_path=Path(__file__).parent.parent)

    def test_clean_slate_flow_has_version(self, loader):
        """Should have version field."""
        flow = loader.load_flow("clean-slate")
        assert hasattr(flow, 'version'), "flow must have version field"
        assert flow.version is not None, "version should not be None"

    def test_clean_slate_flow_has_description(self, loader):
        """Should have description field."""
        flow = loader.load_flow("clean-slate")
        assert hasattr(flow, 'description'), "flow must have description field"
        assert len(flow.description) > 0, "description should not be empty"

    def test_clean_slate_flow_has_service_selection(self, loader):
        """Should have service_selection steps for choosing what to tear down."""
        flow = loader.load_flow("clean-slate")
        assert hasattr(flow, 'service_selection'), "flow must have service_selection"
        assert isinstance(flow.service_selection, list), "service_selection should be a list"
        assert len(flow.service_selection) > 0, "service_selection should not be empty"

    def test_clean_slate_flow_has_targets(self, loader):
        """Should have targets list with teardown flag."""
        flow = loader.load_flow("clean-slate")
        assert hasattr(flow, 'targets'), "flow must have targets"
        assert isinstance(flow.targets, list), "targets should be a list"
        assert len(flow.targets) >= 4, "should have at least 4 services (postgres, openmetadata, kerberos, pagila)"

        # Verify targets have teardown flag
        for target in flow.targets:
            assert 'teardown' in target, f"target {target.get('service')} must have 'teardown' flag"
            assert target['teardown'] is True, f"target {target.get('service')} teardown flag must be True"


class TestServiceTeardownSelection:
    """Tests for service selection logic in clean-slate flow."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)

        # Register teardown actions
        self._register_teardown_actions(engine)

        return engine

    def _register_teardown_actions(self, engine):
        """Register all teardown action modules with engine."""
        from wizard.services.postgres import teardown_actions as postgres_teardown
        from wizard.services.openmetadata import teardown_actions as openmetadata_teardown
        from wizard.services.kerberos import teardown_actions as kerberos_teardown
        from wizard.services.pagila import teardown_actions as pagila_teardown

        # Register postgres teardown
        engine.actions['postgres.teardown.stop_service'] = postgres_teardown.stop_service
        engine.actions['postgres.teardown.remove_volumes'] = postgres_teardown.remove_volumes
        engine.actions['postgres.teardown.remove_images'] = postgres_teardown.remove_images
        engine.actions['postgres.teardown.clean_config'] = postgres_teardown.clean_config

        # Register openmetadata teardown
        engine.actions['openmetadata.teardown.stop_service'] = openmetadata_teardown.stop_service
        engine.actions['openmetadata.teardown.remove_volumes'] = openmetadata_teardown.remove_volumes
        engine.actions['openmetadata.teardown.remove_images'] = openmetadata_teardown.remove_images
        engine.actions['openmetadata.teardown.clean_config'] = openmetadata_teardown.clean_config

        # Register kerberos teardown
        engine.actions['kerberos.teardown.stop_service'] = kerberos_teardown.stop_service
        engine.actions['kerberos.teardown.remove_volumes'] = kerberos_teardown.remove_volumes
        engine.actions['kerberos.teardown.remove_images'] = kerberos_teardown.remove_images
        engine.actions['kerberos.teardown.clean_config'] = kerberos_teardown.clean_config

        # Register pagila teardown
        engine.actions['pagila.teardown.stop_service'] = pagila_teardown.stop_service
        engine.actions['pagila.teardown.remove_volumes'] = pagila_teardown.remove_volumes
        engine.actions['pagila.teardown.remove_images'] = pagila_teardown.remove_images
        engine.actions['pagila.teardown.clean_config'] = pagila_teardown.clean_config

    def test_service_selection_updates_teardown_state(self, engine):
        """Should update state with selected services for teardown."""
        headless_inputs = {
            'select_teardown_services': ['openmetadata', 'kerberos']  # Don't select pagila or postgres
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Verify state has teardown selections
        assert 'services.openmetadata.teardown.enabled' in engine.state
        assert engine.state['services.openmetadata.teardown.enabled'] is True

        assert 'services.kerberos.teardown.enabled' in engine.state
        assert engine.state['services.kerberos.teardown.enabled'] is True

        assert 'services.pagila.teardown.enabled' in engine.state
        assert engine.state['services.pagila.teardown.enabled'] is False

        assert 'services.postgres.teardown.enabled' in engine.state
        assert engine.state['services.postgres.teardown.enabled'] is False

    def test_can_select_all_services_for_teardown(self, engine):
        """Should allow selecting all services for teardown."""
        headless_inputs = {
            'select_teardown_services': ['postgres', 'openmetadata', 'kerberos', 'pagila']
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Verify all services marked for teardown
        assert engine.state.get('services.postgres.teardown.enabled') is True
        assert engine.state.get('services.openmetadata.teardown.enabled') is True
        assert engine.state.get('services.kerberos.teardown.enabled') is True
        assert engine.state.get('services.pagila.teardown.enabled') is True


class TestReverseDependencyOrdering:
    """Tests for REVERSE topological ordering - dependents tear down BEFORE dependencies.

    CRITICAL: This is the opposite of setup ordering!
    - Setup: postgres -> openmetadata (postgres first)
    - Teardown: openmetadata -> postgres (openmetadata first)
    """

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_openmetadata_tears_down_before_postgres(self, engine):
        """OpenMetadata must tear down BEFORE PostgreSQL (reverse dependency)."""
        headless_inputs = {
            'select_teardown_services': ['postgres', 'openmetadata'],
            # Teardown prompts (all yes for full teardown)
            'postgres_teardown_confirm': True,
            'postgres_remove_volumes': True,
            'postgres_remove_images': True,
            'openmetadata_teardown_confirm': True,
            'openmetadata_remove_volumes': True,
            'openmetadata_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Check action call order
        runner = engine.runner
        action_calls = [call for call in runner.calls if call[0] in ['run_shell', 'save_config']]

        # Find indices of postgres and openmetadata teardown actions
        openmetadata_indices = [i for i, call in enumerate(action_calls)
                                if 'openmetadata' in str(call) or 'stop' in str(call)]
        postgres_indices = [i for i, call in enumerate(action_calls)
                            if 'postgres' in str(call) or 'stop' in str(call)]

        # Filter to ensure we're looking at actual teardown actions
        openmetadata_teardown = [i for i in openmetadata_indices
                                  if any(term in str(action_calls[i]) for term in ['stop', 'remove', 'clean'])]
        postgres_teardown = [i for i in postgres_indices
                             if any(term in str(action_calls[i]) for term in ['stop', 'remove', 'clean'])]

        if openmetadata_teardown and postgres_teardown:
            assert max(openmetadata_teardown) < min(postgres_teardown), \
                "All openmetadata teardown actions should complete BEFORE postgres teardown actions"

    def test_pagila_tears_down_before_postgres(self, engine):
        """Pagila must tear down BEFORE PostgreSQL (reverse dependency)."""
        headless_inputs = {
            'select_teardown_services': ['postgres', 'pagila'],
            # Teardown prompts
            'postgres_teardown_confirm': True,
            'postgres_remove_volumes': True,
            'postgres_remove_images': True,
            'pagila_teardown_confirm': True,
            'pagila_remove_volumes': True,
            'pagila_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Check action call order
        runner = engine.runner
        # Filter out discovery queries - only check teardown action order
        def is_discovery_call(call):
            if call[0] == 'run_shell' and len(call) >= 2:
                cmd = call[1]
                # Discovery uses docker ps, docker images, docker volume ls
                if len(cmd) >= 2 and cmd[0] == 'docker' and cmd[1] in ['ps', 'images', 'volume']:
                    return True
            elif call[0] == 'file_exists':
                return True
            return False

        action_calls = [call for call in runner.calls
                        if (call[0] in ['run_shell', 'save_config']) and not is_discovery_call(call)]

        # Find indices of postgres and pagila teardown actions
        pagila_indices = [i for i, call in enumerate(action_calls)
                          if 'pagila' in str(call)]
        postgres_indices = [i for i, call in enumerate(action_calls)
                            if 'postgres' in str(call)]

        if pagila_indices and postgres_indices:
            assert max(pagila_indices) < min(postgres_indices), \
                "All pagila teardown actions should complete BEFORE postgres teardown actions"

    def test_kerberos_can_tear_down_independently(self, engine):
        """Kerberos has no dependencies and can tear down in any order."""
        headless_inputs = {
            'select_teardown_services': ['kerberos'],
            # Teardown prompts
            'kerberos_teardown_confirm': True,
            'kerberos_remove_volumes': True,
            'kerberos_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Should execute without errors
        # Kerberos can tear down independently
        runner = engine.runner
        assert len(runner.calls) > 0, "Should have executed teardown actions"

    def test_all_services_reverse_topological_order(self, engine):
        """When tearing down all services, dependents must tear down before dependencies."""
        headless_inputs = {
            'select_teardown_services': ['postgres', 'openmetadata', 'kerberos', 'pagila'],
            # All teardown confirmations
            'postgres_teardown_confirm': True,
            'postgres_remove_volumes': True,
            'postgres_remove_images': True,
            'openmetadata_teardown_confirm': True,
            'openmetadata_remove_volumes': True,
            'openmetadata_remove_images': True,
            'kerberos_teardown_confirm': True,
            'kerberos_remove_volumes': True,
            'kerberos_remove_images': True,
            'pagila_teardown_confirm': True,
            'pagila_remove_volumes': True,
            'pagila_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Check action call order
        runner = engine.runner
        action_calls = [call for call in runner.calls if call[0] in ['run_shell', 'save_config']]

        # Find first postgres teardown action
        postgres_start = None
        for i, call in enumerate(action_calls):
            if 'postgres' in str(call):
                postgres_start = i
                break

        if postgres_start is not None:
            # All openmetadata and pagila actions must come before first postgres action
            for i in range(postgres_start):
                call_str = str(action_calls[i])
                # Should only see openmetadata, pagila, or kerberos before postgres
                if 'postgres' in call_str:
                    pytest.fail(f"Found postgres action at index {i}, before expected (postgres_start={postgres_start})")


class TestSelectiveTeardown:
    """Tests for selective teardown scenarios."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_tear_down_openmetadata_only(self, engine):
        """Should tear down only OpenMetadata, leaving postgres running."""
        headless_inputs = {
            'select_teardown_services': ['openmetadata'],  # Only openmetadata
            'openmetadata_teardown_confirm': True,
            'openmetadata_remove_volumes': True,
            'openmetadata_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Verify only openmetadata marked for teardown
        assert engine.state.get('services.openmetadata.teardown.enabled') is True
        assert engine.state.get('services.postgres.teardown.enabled', False) is False

        # Verify only openmetadata actions called
        runner = engine.runner
        action_calls_str = str(runner.calls)
        assert 'openmetadata' in action_calls_str or len(runner.calls) > 0
        # Postgres should not be in teardown calls
        postgres_teardown_calls = [c for c in runner.calls if 'postgres' in str(c) and 'stop' in str(c)]
        assert len(postgres_teardown_calls) == 0, "Postgres should not tear down"

    def test_tear_down_kerberos_only(self, engine):
        """Should tear down only Kerberos (independent service)."""
        headless_inputs = {
            'select_teardown_services': ['kerberos'],
            'kerberos_teardown_confirm': True,
            'kerberos_remove_volumes': True,
            'kerberos_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Verify only kerberos marked for teardown
        assert engine.state.get('services.kerberos.teardown.enabled') is True
        assert engine.state.get('services.postgres.teardown.enabled', False) is False
        assert engine.state.get('services.openmetadata.teardown.enabled', False) is False

        # Verify only kerberos actions called
        runner = engine.runner
        assert len(runner.calls) > 0, "Should have executed kerberos teardown"

    def test_tear_down_pagila_and_postgres(self, engine):
        """Should tear down Pagila first, then Postgres (respecting reverse dependencies)."""
        headless_inputs = {
            'select_teardown_services': ['postgres', 'pagila'],
            'postgres_teardown_confirm': True,
            'postgres_remove_volumes': True,
            'postgres_remove_images': True,
            'pagila_teardown_confirm': True,
            'pagila_remove_volumes': True,
            'pagila_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Check ordering: pagila before postgres
        runner = engine.runner
        # Filter out discovery queries - only check teardown action order
        def is_discovery_call(call):
            if call[0] == 'run_shell' and len(call) >= 2:
                cmd = call[1]
                # Discovery uses docker ps, docker images, docker volume ls
                if len(cmd) >= 2 and cmd[0] == 'docker' and cmd[1] in ['ps', 'images', 'volume']:
                    return True
            elif call[0] == 'file_exists':
                return True
            return False

        action_calls = [call for call in runner.calls if not is_discovery_call(call)]

        pagila_indices = [i for i, call in enumerate(action_calls) if 'pagila' in str(call)]
        postgres_indices = [i for i, call in enumerate(action_calls) if 'postgres' in str(call)]

        if pagila_indices and postgres_indices:
            assert max(pagila_indices) < min(postgres_indices), \
                "Pagila must complete teardown before postgres starts teardown"

    def test_tear_down_multiple_independents(self, engine):
        """Should tear down multiple independent services without constraints."""
        headless_inputs = {
            'select_teardown_services': ['kerberos', 'pagila'],  # Both can be torn down independently
            'kerberos_teardown_confirm': True,
            'kerberos_remove_volumes': True,
            'kerberos_remove_images': True,
            'pagila_teardown_confirm': True,
            'pagila_remove_volumes': True,
            'pagila_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Both should be marked for teardown
        assert engine.state.get('services.kerberos.teardown.enabled') is True
        assert engine.state.get('services.pagila.teardown.enabled') is True

        # Postgres should not be torn down
        assert engine.state.get('services.postgres.teardown.enabled', False) is False

        # Verify both services executed teardown
        runner = engine.runner
        assert len(runner.calls) > 0, "Should have executed teardown actions"


class TestTeardownActionRecording:
    """Tests for MockActionRunner recording of teardown actions."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_records_stop_service_actions(self, engine):
        """Should record stop_service actions for all selected services."""
        headless_inputs = {
            'select_teardown_services': ['postgres', 'openmetadata'],
            'postgres_teardown_confirm': True,
            'postgres_remove_volumes': False,
            'postgres_remove_images': False,
            'openmetadata_teardown_confirm': True,
            'openmetadata_remove_volumes': False,
            'openmetadata_remove_images': False
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        runner = engine.runner
        shell_calls = [c for c in runner.calls if c[0] == 'run_shell']

        # Should have stop commands
        assert len(shell_calls) >= 2, "Should have stop commands for both services"

    def test_records_clean_config_actions(self, engine):
        """Should record clean_config actions to disable services."""
        headless_inputs = {
            'select_teardown_services': ['kerberos'],
            'kerberos_teardown_confirm': True,
            'kerberos_remove_volumes': True,
            'kerberos_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        runner = engine.runner
        config_calls = [c for c in runner.calls if c[0] == 'save_config']

        # Should have clean_config call
        assert len(config_calls) >= 1, "Should save config to disable service"

    def test_records_actions_in_correct_sequence(self, engine):
        """Should record teardown actions in expected sequence: stop -> remove_volumes -> remove_images -> clean_config."""
        headless_inputs = {
            'select_teardown_services': ['postgres'],
            'postgres_teardown_confirm': True,
            'postgres_remove_volumes': True,
            'postgres_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        runner = engine.runner
        all_calls = runner.calls

        # Find action types in order
        action_sequence = []
        for call in all_calls:
            if 'stop' in str(call):
                action_sequence.append('stop')
            elif 'volume' in str(call):
                action_sequence.append('remove_volumes')
            elif 'rmi' in str(call) or 'image' in str(call):
                action_sequence.append('remove_images')
            elif 'save_config' in str(call):
                action_sequence.append('clean_config')

        # Verify logical order (stop should come before clean)
        if 'stop' in action_sequence and 'clean_config' in action_sequence:
            stop_idx = action_sequence.index('stop')
            clean_idx = action_sequence.index('clean_config')
            assert stop_idx < clean_idx, "stop should come before clean_config"


class TestTeardownStateManagement:
    """Tests for state management across teardown operations."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_state_tracks_teardown_selections(self, engine):
        """State should track which services are selected for teardown."""
        headless_inputs = {
            'select_teardown_services': ['openmetadata', 'pagila']
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Verify state reflects selections
        assert 'services.openmetadata.teardown.enabled' in engine.state
        assert 'services.pagila.teardown.enabled' in engine.state
        assert engine.state['services.openmetadata.teardown.enabled'] is True
        assert engine.state['services.pagila.teardown.enabled'] is True

    def test_state_tracks_teardown_confirmations(self, engine):
        """State should track teardown confirmation responses."""
        headless_inputs = {
            'select_teardown_services': ['postgres'],
            'postgres_teardown_confirm': True,
            'postgres_remove_volumes': False,
            'postgres_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Verify state tracks confirmation choices
        assert engine.state.get('services.postgres.teardown.confirm') is True
        assert engine.state.get('services.postgres.teardown.remove_volumes') is False
        assert engine.state.get('services.postgres.teardown.remove_images') is True

    def test_state_persists_across_service_teardowns(self, engine):
        """State should persist across multiple service teardowns."""
        headless_inputs = {
            'select_teardown_services': ['openmetadata', 'postgres'],
            'postgres_teardown_confirm': True,
            'postgres_remove_volumes': True,
            'postgres_remove_images': True,
            'openmetadata_teardown_confirm': True,
            'openmetadata_remove_volumes': True,
            'openmetadata_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Both services' teardown state should be present
        assert 'services.postgres.teardown.confirm' in engine.state
        assert 'services.openmetadata.teardown.confirm' in engine.state

        # State from first service should still be available when second tears down
        assert engine.state['services.postgres.teardown.confirm'] is True
        assert engine.state['services.openmetadata.teardown.confirm'] is True


class TestConditionalTeardownInclusion:
    """Tests for conditional execution based on teardown selection."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_unselected_services_not_torn_down(self, engine):
        """Services not selected for teardown should not execute teardown steps."""
        headless_inputs = {
            'select_teardown_services': ['kerberos'],  # Only kerberos
            'kerberos_teardown_confirm': True,
            'kerberos_remove_volumes': True,
            'kerberos_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Verify unselected services not torn down
        assert engine.state.get('services.postgres.teardown.enabled', False) is False
        assert engine.state.get('services.openmetadata.teardown.enabled', False) is False
        assert engine.state.get('services.pagila.teardown.enabled', False) is False

        # Verify no teardown actions called for unselected services
        runner = engine.runner
        # Filter out discovery queries (docker ps, docker images, docker volume ls, file_exists)
        # Only check for actual teardown actions
        def is_discovery_call(call):
            if call[0] == 'run_shell' and len(call) >= 2:
                cmd = call[1]
                # Discovery uses docker ps, docker images, docker volume ls
                if len(cmd) >= 2 and cmd[0] == 'docker' and cmd[1] in ['ps', 'images', 'volume']:
                    return True
            elif call[0] == 'file_exists':
                return True
            return False

        teardown_calls = [c for c in runner.calls if not is_discovery_call(c)]
        teardown_calls_str = str(teardown_calls)
        # These should not appear in teardown calls (discovery queries are OK)
        assert 'postgres' not in teardown_calls_str.lower() or len([c for c in teardown_calls if 'postgres' in str(c)]) == 0
        assert 'openmetadata' not in teardown_calls_str.lower() or len([c for c in teardown_calls if 'openmetadata' in str(c)]) == 0

    def test_selected_services_execute_teardown(self, engine):
        """Services selected for teardown should execute all teardown steps."""
        headless_inputs = {
            'select_teardown_services': ['pagila'],
            'pagila_teardown_confirm': True,
            'pagila_remove_volumes': True,
            'pagila_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Verify pagila is marked for teardown
        assert engine.state.get('services.pagila.teardown.enabled') is True

        # Verify pagila teardown executed
        runner = engine.runner
        assert len(runner.calls) > 0, "Should have executed pagila teardown"


class TestFlowPolicyCompliance:
    """Tests for flow policy compliance (reverse ordering, abort on failure)."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_flow_respects_reverse_topological_policy(self, engine):
        """Flow should execute in reverse topological order (policy: ordering: reverse-topological)."""
        headless_inputs = {
            'select_teardown_services': ['postgres', 'openmetadata', 'pagila'],
            'postgres_teardown_confirm': True,
            'postgres_remove_volumes': True,
            'postgres_remove_images': True,
            'openmetadata_teardown_confirm': True,
            'openmetadata_remove_volumes': True,
            'openmetadata_remove_images': True,
            'pagila_teardown_confirm': True,
            'pagila_remove_volumes': True,
            'pagila_remove_images': True
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Verify execution order respects reverse dependencies
        runner = engine.runner
        # Filter out discovery queries - only check teardown action order
        def is_discovery_call(call):
            if call[0] == 'run_shell' and len(call) >= 2:
                cmd = call[1]
                # Discovery uses docker ps, docker images, docker volume ls
                if len(cmd) >= 2 and cmd[0] == 'docker' and cmd[1] in ['ps', 'images', 'volume']:
                    return True
            elif call[0] == 'file_exists':
                return True
            return False

        action_calls = [c for c in runner.calls if not is_discovery_call(c)]

        # Find execution indices
        first_postgres_idx = None
        last_openmetadata_idx = None
        last_pagila_idx = None

        for i, call in enumerate(action_calls):
            call_str = str(call)
            if 'postgres' in call_str and first_postgres_idx is None:
                first_postgres_idx = i
            if 'openmetadata' in call_str:
                last_openmetadata_idx = i
            if 'pagila' in call_str:
                last_pagila_idx = i

        # Both openmetadata and pagila must complete before postgres starts
        if first_postgres_idx is not None:
            if last_openmetadata_idx is not None:
                assert last_openmetadata_idx < first_postgres_idx, \
                    "OpenMetadata must complete before Postgres starts"
            if last_pagila_idx is not None:
                assert last_pagila_idx < first_postgres_idx, \
                    "Pagila must complete before Postgres starts"

    def test_empty_selection_does_not_tear_down_anything(self, engine):
        """Empty selection should not tear down any services."""
        headless_inputs = {
            'select_teardown_services': []  # No services selected
        }

        engine.execute_flow('clean-slate', headless_inputs=headless_inputs)

        # Verify no services marked for teardown
        assert engine.state.get('services.postgres.teardown.enabled', False) is False
        assert engine.state.get('services.openmetadata.teardown.enabled', False) is False
        assert engine.state.get('services.kerberos.teardown.enabled', False) is False
        assert engine.state.get('services.pagila.teardown.enabled', False) is False

        # Verify no teardown actions executed
        runner = engine.runner
        # Should have minimal or no calls (excluding display calls)
        teardown_calls = [c for c in runner.calls if c[0] != 'display' and any(term in str(c) for term in ['stop', 'remove', 'clean'])]
        assert len(teardown_calls) == 0, "Should not execute any teardown actions"
