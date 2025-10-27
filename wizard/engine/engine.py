"""Core wizard engine - executes specs with DI."""

import re
from typing import Dict, Any, Optional, List
from pathlib import Path
from .loader import SpecLoader
from .runner import ActionRunner
from .schema import Step, ServiceSpec


class WizardEngine:
    """
    Executes wizard specs with dependency injection.

    Key responsibilities:
    - Load service specs and flows
    - Execute steps with state management
    - Inject runner for side effects
    - Support headless mode for testing
    """

    def __init__(self, runner: ActionRunner, base_path: Optional[Path] = None):
        """
        Initialize the wizard engine.

        Args:
            runner: ActionRunner implementation for side effects
            base_path: Base directory for wizard specs (default: ./wizard)
        """
        self.runner = runner
        self.loader = SpecLoader(base_path=base_path)
        self.state: Dict[str, Any] = {}
        self.validators: Dict[str, callable] = {}
        self.actions: Dict[str, callable] = {}

    def _interpolate_prompt(self, prompt: str, state: dict) -> str:
        """Replace {key} placeholders with state values.

        Args:
            prompt: Template string with {placeholders}
            state: Current wizard state

        Returns:
            Interpolated string with values filled in

        Examples:
            >>> engine._interpolate_prompt("Found {count} items", {'count': 5})
            'Found 5 items'
        """
        def replacer(match):
            key = match.group(1)
            value = state.get(key, f'{{{key}}}')  # Keep {key} if not found
            return str(value)

        return re.sub(r'\{([^}]+)\}', replacer, prompt)

    def _execute_step(self, step: Step, headless_inputs: Optional[Dict] = None) -> Any:
        """
        Execute a single step.

        Args:
            step: Step to execute
            headless_inputs: Dict of {step_id: value} for testing

        Returns:
            The value captured from this step
        """
        # Handle display steps
        if step.type == 'display':
            if step.prompt:
                message = self._interpolate_prompt(step.prompt, self.state)
                self.runner.display(message)
            return  # Display steps don't collect input

        # Handle discovery action
        if step.action == 'discovery.scan_all_services':
            from wizard.engine.discovery import DiscoveryEngine

            discovery_engine = DiscoveryEngine(self.runner)
            results = discovery_engine.discover_all()
            summary = discovery_engine.get_summary(results)

            # Store in state
            self.state['discovery_results'] = results
            self.state['total_artifacts'] = (
                summary['total_containers'] +
                summary['total_images'] +
                summary['total_volumes']
            )
            return None

        # Display prompts for interactive steps
        if step.prompt and step.type in ['string', 'boolean', 'enum', 'integer']:
            prompt_text = self._interpolate_prompt(step.prompt, self.state)
            self.runner.display(prompt_text)  # Show prompt before getting input

        # Get input value
        if headless_inputs is not None and step.id in headless_inputs:
            value = headless_inputs[step.id]
            has_input = True
        else:
            # In real mode, would prompt user here
            # In headless mode without input, use empty string (will trigger default)
            value = '' if headless_inputs is not None else None
            has_input = False

        # Handle default values (only if no explicit input provided or input is empty string)
        if not has_input or value == '':
            if step.default_from and step.default_from in self.state:
                value = self.state[step.default_from]
            elif step.default_value is not None:
                value = step.default_value
            else:
                # No default available and no input provided
                value = ''

        # Validate if validator specified
        if step.validator and step.validator in self.validators:
            validator_fn = self.validators[step.validator]
            # Only validate if we have a non-empty value
            if value:
                value = validator_fn(value, self.state)

        # Store in state if state_key specified
        if step.state_key:
            self.state[step.state_key] = value

        # Execute action if specified
        if step.action and step.action in self.actions:
            action_fn = self.actions[step.action]
            action_fn(self.state, self.runner)

        return value

    def _resolve_next(self, step: Step, new_value: Any, old_value: Any = None) -> Optional[str]:
        """
        Resolve the next step ID based on step configuration.

        Args:
            step: Current step
            new_value: New value entered
            old_value: Previous value (for when_changed/when_unchanged)

        Returns:
            Next step ID or None
        """
        if step.next is None:
            return None

        # Simple string next
        if isinstance(step.next, str):
            return step.next

        # Conditional next based on change or value
        if isinstance(step.next, dict):
            # when_value: branch based on the value
            if 'when_value' in step.next:
                value_map = step.next['when_value']
                if new_value in value_map:
                    return value_map[new_value]
                return None

            # when_changed/when_unchanged: branch based on change
            if 'when_changed' in step.next and 'when_unchanged' in step.next:
                if new_value != old_value:
                    return step.next['when_changed']
                else:
                    return step.next['when_unchanged']

        return None

    def _get_step_by_id(self, service_spec: ServiceSpec, step_id: str) -> Optional[Step]:
        """
        Find a step by ID in a service spec.

        Args:
            service_spec: Service specification
            step_id: Step identifier

        Returns:
            Step instance or None
        """
        for step in service_spec.steps:
            if step.id == step_id:
                return step
        return None

    def _execute_flow_steps(self, steps: List[Step], headless_inputs: Optional[Dict] = None):
        """
        Execute flow-level steps (discovery, conditionals, etc.).

        Args:
            steps: List of flow steps
            headless_inputs: Dict of {step_id: value} for testing
        """
        if not steps:
            return

        # Start with first step
        current_step_id = steps[0].id

        while current_step_id:
            # Find step by ID
            step = None
            for s in steps:
                if s.id == current_step_id:
                    step = s
                    break

            if not step:
                break

            # Handle conditional steps
            if step.type == 'conditional':
                condition = step.condition if hasattr(step, 'condition') else None
                if condition:
                    # Evaluate condition (simple equality check for now)
                    # Format: "state.key == value" or "state.key == 0"
                    condition_met = self._evaluate_condition(condition)

                    # Get next step based on condition
                    next_dict = step.next
                    if isinstance(next_dict, dict):
                        if condition_met:
                            current_step_id = next_dict.get('when_true')
                        else:
                            current_step_id = next_dict.get('when_false')
                    else:
                        current_step_id = next_dict
                else:
                    current_step_id = None
                continue

            # Execute regular step
            self._execute_step(step, headless_inputs)

            # Resolve next step
            if step.next is None:
                # Explicit termination
                break
            elif isinstance(step.next, str):
                current_step_id = step.next
            else:
                # Complex next logic would go here
                break

    def _evaluate_condition(self, condition: str) -> bool:
        """
        Evaluate a condition string against current state.

        Args:
            condition: Condition string (e.g., "state.total_artifacts == 0")

        Returns:
            True if condition is met
        """
        # Simple condition evaluation for now
        # Format: "state.key == value"
        if '==' in condition:
            parts = condition.split('==')
            if len(parts) == 2:
                left = parts[0].strip()
                right = parts[1].strip()

                # Extract state key (remove "state." prefix)
                if left.startswith('state.'):
                    key = left[6:]  # Remove "state."
                    state_value = self.state.get(key)

                    # Parse right side
                    try:
                        expected_value = int(right)
                    except ValueError:
                        expected_value = right.strip('"\'')

                    return state_value == expected_value

        return False

    def _execute_service(self, service_spec: ServiceSpec, headless_inputs: Optional[Dict] = None):
        """
        Execute all steps for a service.

        Args:
            service_spec: Service specification
            headless_inputs: Dict of {step_id: value} for testing
        """
        if not service_spec.steps:
            return

        # Start with first step
        current_step_id = service_spec.steps[0].id

        while current_step_id:
            step = self._get_step_by_id(service_spec, current_step_id)
            if not step:
                break

            # Track old value for conditional next
            old_value = self.state.get(step.state_key) if step.state_key else None

            # Execute step
            new_value = self._execute_step(step, headless_inputs)

            # Resolve next step
            next_step_id = self._resolve_next(step, new_value, old_value)

            # If no explicit next, go to next step in sequence
            if next_step_id is None and step.next is None:
                current_index = next(
                    (i for i, s in enumerate(service_spec.steps) if s.id == current_step_id),
                    None
                )
                if current_index is not None and current_index + 1 < len(service_spec.steps):
                    next_step_id = service_spec.steps[current_index + 1].id

            current_step_id = next_step_id

    def execute_flow(self, flow_name: str, headless_inputs: Optional[Dict] = None):
        """
        Execute a flow orchestrating multiple services.

        Args:
            flow_name: Name of flow to execute (e.g., 'setup')
            headless_inputs: Dict of {step_id: value} for testing
        """
        # Load flow spec
        flow = self.loader.load_flow(flow_name)

        # Check if this is a teardown flow
        is_teardown_flow = any(target.get('teardown', False) for target in flow.targets)

        # Initialize service states
        for target in flow.targets:
            service_name = target['service']
            enabled = target.get('enabled', False)

            if is_teardown_flow:
                # For teardown flows, use teardown.enabled state key
                self.state[f'services.{service_name}.teardown.enabled'] = enabled
            else:
                # For setup flows, use regular enabled state key
                self.state[f'services.{service_name}.enabled'] = enabled

        # Execute flow-level steps (e.g., discovery)
        if flow.steps:
            self._execute_flow_steps(flow.steps, headless_inputs)

        # Execute service selection steps
        if flow.service_selection:
            for step in flow.service_selection:
                if step.id in (headless_inputs or {}):
                    selected = headless_inputs[step.id]
                    # Store selected services
                    if step.state_key:
                        self.state[step.state_key] = selected

                    # Update service enabled flags based on selection
                    for target in flow.targets:
                        service_name = target['service']

                        if is_teardown_flow:
                            # For teardown, services are enabled if explicitly selected
                            if service_name in selected:
                                self.state[f'services.{service_name}.teardown.enabled'] = True
                            else:
                                self.state[f'services.{service_name}.teardown.enabled'] = False
                        else:
                            # For setup, postgres always enabled, others based on selection
                            if service_name == 'postgres':
                                self.state[f'services.{service_name}.enabled'] = True
                            elif service_name in selected:
                                self.state[f'services.{service_name}.enabled'] = True
                            else:
                                self.state[f'services.{service_name}.enabled'] = False

        # Auto-register service validators and actions
        self._auto_register_services(is_teardown_flow)

        # Determine ordering policy
        ordering = flow.policy.get('ordering', 'topological') if flow.policy else 'topological'

        # Execute services based on ordering policy
        if ordering == 'reverse-topological':
            self._execute_services_reverse_topological(flow, headless_inputs, is_teardown_flow)
        else:
            self._execute_services_topological(flow, headless_inputs, is_teardown_flow)

    def _execute_services_topological(self, flow, headless_inputs: Optional[Dict], is_teardown_flow: bool):
        """Execute services in normal topological order (for setup)."""
        executed = set()

        def can_execute(target):
            """Check if service dependencies are satisfied."""
            depends_on = target.get('depends_on', [])
            return all(dep in executed for dep in depends_on)

        while True:
            # Find a service that can be executed
            ready = None
            for target in flow.targets:
                service_name = target['service']
                if service_name in executed:
                    continue

                state_key = f'services.{service_name}.teardown.enabled' if is_teardown_flow else f'services.{service_name}.enabled'
                if not self.state.get(state_key, False):
                    # Mark as executed (skipped) so it doesn't block dependents
                    executed.add(service_name)
                    continue
                if can_execute(target):
                    ready = target
                    break

            if ready is None:
                break

            # Execute the ready service
            service_name = ready['service']
            is_teardown = ready.get('teardown', False)
            service_spec = self.loader.load_service_spec(service_name, teardown=is_teardown)
            self._execute_service(service_spec, headless_inputs)
            executed.add(service_name)

    def _execute_services_reverse_topological(self, flow, headless_inputs: Optional[Dict], is_teardown_flow: bool):
        """Execute services in reverse topological order (for teardown).

        In reverse topological order, dependents execute BEFORE their dependencies.
        For example, if openmetadata depends on postgres, openmetadata tears down first.

        The key insight: In teardown, depends_on means "I depended on this in setup,
        so I must tear down BEFORE it". We need to check if anything else depends on
        the current service, not if this service's dependencies are satisfied.
        """
        executed = set()

        def can_execute_teardown(target):
            """Check if service can tear down (nothing depends on it anymore)."""
            service_name = target['service']
            # Check if any non-executed service depends on this one
            for other_target in flow.targets:
                other_name = other_target['service']
                if other_name in executed:
                    continue
                other_depends_on = other_target.get('depends_on', [])
                if service_name in other_depends_on:
                    # Someone still depends on us, we can't tear down yet
                    return False
            return True

        # Execute services in reverse topological order
        while True:
            ready = None
            for target in flow.targets:
                service_name = target['service']
                if service_name in executed:
                    continue

                state_key = f'services.{service_name}.teardown.enabled' if is_teardown_flow else f'services.{service_name}.enabled'
                if not self.state.get(state_key, False):
                    # Mark as executed (skipped) so it doesn't block dependents
                    executed.add(service_name)
                    continue

                if can_execute_teardown(target):
                    ready = target
                    break

            if ready is None:
                break

            # Execute the ready service
            service_name = ready['service']
            is_teardown = ready.get('teardown', False)
            service_spec = self.loader.load_service_spec(service_name, teardown=is_teardown)
            self._execute_service(service_spec, headless_inputs)
            executed.add(service_name)

    def _auto_register_services(self, is_teardown_flow: bool = False):
        """Auto-register validators and actions from service modules.

        Args:
            is_teardown_flow: If True, also register teardown actions
        """
        # Only register if not already registered (to avoid conflicts with manual registration)
        if 'postgres.validate_image_url' in self.validators:
            return  # Already registered

        try:
            from wizard.services import postgres, openmetadata, kerberos, pagila

            # Register postgres
            self.validators['postgres.validate_image_url'] = postgres.validate_image_url
            self.validators['postgres.validate_port'] = postgres.validate_port
            self.actions['postgres.save_config'] = postgres.save_config
            self.actions['postgres.init_database'] = postgres.init_database
            self.actions['postgres.start_service'] = postgres.start_service

            # Register openmetadata
            self.validators['openmetadata.validate_image_url'] = openmetadata.validate_image_url
            self.validators['openmetadata.validate_port'] = openmetadata.validate_port
            self.actions['openmetadata.save_config'] = openmetadata.save_config
            self.actions['openmetadata.start_service'] = openmetadata.start_service

            # Register kerberos
            self.validators['kerberos.validate_domain'] = kerberos.validate_domain
            self.validators['kerberos.validate_image_url'] = kerberos.validate_image_url
            self.actions['kerberos.test_kerberos'] = kerberos.test_kerberos
            self.actions['kerberos.save_config'] = kerberos.save_config

            # Register pagila
            self.validators['pagila.validate_git_url'] = pagila.validate_git_url
            self.actions['pagila.save_config'] = pagila.save_config
            self.actions['pagila.install_pagila'] = pagila.install_pagila

            # Register teardown actions if this is a teardown flow
            if is_teardown_flow:
                from wizard.services.postgres import teardown_actions as postgres_teardown
                from wizard.services.openmetadata import teardown_actions as openmetadata_teardown
                from wizard.services.kerberos import teardown_actions as kerberos_teardown
                from wizard.services.pagila import teardown_actions as pagila_teardown

                # Register postgres teardown (uses teardown. prefix in spec)
                self.actions['postgres.teardown.stop_service'] = postgres_teardown.stop_service
                self.actions['postgres.teardown.remove_volumes'] = postgres_teardown.remove_volumes
                self.actions['postgres.teardown.remove_images'] = postgres_teardown.remove_images
                self.actions['postgres.teardown.clean_config'] = postgres_teardown.clean_config

                # Register openmetadata teardown (no teardown. prefix in spec, but register with prefix for tests)
                self.actions['openmetadata.stop_service'] = openmetadata_teardown.stop_service
                self.actions['openmetadata.remove_volumes'] = openmetadata_teardown.remove_volumes
                self.actions['openmetadata.remove_images'] = openmetadata_teardown.remove_images
                self.actions['openmetadata.clean_config'] = openmetadata_teardown.clean_config
                self.actions['openmetadata.teardown.stop_service'] = openmetadata_teardown.stop_service
                self.actions['openmetadata.teardown.remove_volumes'] = openmetadata_teardown.remove_volumes
                self.actions['openmetadata.teardown.remove_images'] = openmetadata_teardown.remove_images
                self.actions['openmetadata.teardown.clean_config'] = openmetadata_teardown.clean_config

                # Register kerberos teardown (no teardown. prefix in spec, but register with prefix for tests)
                self.actions['kerberos.stop_service'] = kerberos_teardown.stop_service
                self.actions['kerberos.remove_keytabs'] = kerberos_teardown.remove_keytabs
                self.actions['kerberos.remove_images'] = kerberos_teardown.remove_images
                self.actions['kerberos.clean_configuration'] = kerberos_teardown.clean_configuration
                self.actions['kerberos.teardown.stop_service'] = kerberos_teardown.stop_service
                self.actions['kerberos.teardown.remove_volumes'] = kerberos_teardown.remove_volumes
                self.actions['kerberos.teardown.remove_images'] = kerberos_teardown.remove_images
                self.actions['kerberos.teardown.clean_config'] = kerberos_teardown.clean_config

                # Register pagila teardown (no teardown. prefix in spec, but register with prefix for tests)
                self.actions['pagila.drop_database'] = pagila_teardown.drop_database
                self.actions['pagila.remove_repo'] = pagila_teardown.remove_repo
                self.actions['pagila.clean_config'] = pagila_teardown.clean_config
                self.actions['pagila.teardown.stop_service'] = pagila_teardown.stop_service
                self.actions['pagila.teardown.remove_volumes'] = pagila_teardown.remove_volumes
                self.actions['pagila.teardown.remove_images'] = pagila_teardown.remove_images
                self.actions['pagila.teardown.clean_config'] = pagila_teardown.clean_config

        except ImportError:
            # Services not available, continue without them
            pass
