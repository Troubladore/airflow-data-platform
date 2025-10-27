"""Discovery engine for finding actual platform artifacts on the system."""

from typing import Dict, List, Any


class DiscoveryEngine:
    """Aggregates discovery from all services."""

    def __init__(self, runner):
        """Initialize with action runner."""
        self.runner = runner
        self._load_service_modules()

    def _load_service_modules(self):
        """Dynamically import service discovery modules."""
        self.service_modules = {}

        services = ['postgres', 'openmetadata', 'kerberos', 'pagila']

        for service_name in services:
            try:
                # Dynamically import discovery module
                module = __import__(
                    f'wizard.services.{service_name}.discovery',
                    fromlist=['discovery']
                )
                self.service_modules[service_name] = module
            except ImportError:
                # Service discovery module doesn't exist yet - that's ok
                self.service_modules[service_name] = None

    def discover_all(self) -> Dict[str, Any]:
        """Discover artifacts from all services."""
        results = {}

        for service_name, module in self.service_modules.items():
            if module is None:
                # Service discovery not implemented yet
                results[service_name] = {
                    'containers': [],
                    'images': [],
                    'volumes': [],
                    'files': []
                }
                continue

            # Call service discovery functions
            try:
                results[service_name] = {
                    'containers': module.discover_containers(self.runner),
                    'images': module.discover_images(self.runner),
                    'volumes': module.discover_volumes(self.runner),
                    'files': module.discover_files(self.runner)
                }
            except AttributeError:
                # Service module exists but missing functions
                results[service_name] = {
                    'containers': [],
                    'images': [],
                    'volumes': [],
                    'files': []
                }

        return results

    def get_summary(self, results: Dict[str, Any]) -> Dict[str, Any]:
        """Aggregate discovery results into summary counts."""
        total_containers = 0
        total_images = 0
        total_volumes = 0

        for service_results in results.values():
            total_containers += len(service_results.get('containers', []))
            total_images += len(service_results.get('images', []))
            total_volumes += len(service_results.get('volumes', []))

        return {
            'total_containers': total_containers,
            'total_images': total_images,
            'total_volumes': total_volumes,
            'services_found': [
                name for name, results in results.items()
                if any(len(v) > 0 for v in results.values() if isinstance(v, list))
            ]
        }
