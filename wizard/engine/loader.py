"""SpecLoader - loads and validates YAML specifications."""

import yaml
from pathlib import Path
from typing import Optional
from .schema import ServiceSpec, Flow


class SpecLoader:
    """
    Loads service specifications and flows from YAML files.

    Validates structure using Pydantic models.
    """

    def __init__(self, base_path: Optional[Path] = None):
        """
        Initialize loader.

        Args:
            base_path: Base directory for wizard specs (default: ./wizard)
        """
        if base_path is None:
            base_path = Path.cwd() / "wizard"
        self.base_path = Path(base_path)

    def load_service_spec(self, service_name: str, teardown: bool = False) -> ServiceSpec:
        """
        Load a service specification from YAML.

        Args:
            service_name: Name of service (e.g., 'postgres')
            teardown: If True, load teardown-spec.yaml instead of spec.yaml

        Returns:
            Validated ServiceSpec instance

        Raises:
            FileNotFoundError: If spec file doesn't exist
            ValidationError: If YAML doesn't match schema
        """
        spec_filename = "teardown-spec.yaml" if teardown else "spec.yaml"
        spec_path = self.base_path / "services" / service_name / spec_filename

        if not spec_path.exists():
            raise FileNotFoundError(f"Service spec not found: {spec_path}")

        with open(spec_path, 'r') as f:
            data = yaml.safe_load(f)

        return ServiceSpec(**data)

    def load_flow(self, flow_name: str) -> Flow:
        """
        Load a flow definition from YAML.

        Args:
            flow_name: Name of flow (e.g., 'setup')

        Returns:
            Validated Flow instance

        Raises:
            FileNotFoundError: If flow file doesn't exist
            ValidationError: If YAML doesn't match schema
        """
        flow_path = self.base_path / "flows" / f"{flow_name}.yaml"

        if not flow_path.exists():
            raise FileNotFoundError(f"Flow not found: {flow_path}")

        with open(flow_path, 'r') as f:
            data = yaml.safe_load(f)

        return Flow(**data)
