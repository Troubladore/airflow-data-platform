"""ActionRunner interface - all side effects go here."""

from abc import ABC, abstractmethod
from typing import List, Dict, Any


class ActionRunner(ABC):
    """Interface for executing side effects."""

    @abstractmethod
    def save_config(self, config: dict, path: str) -> None:
        """Save configuration to YAML file."""
        pass

    @abstractmethod
    def run_shell(self, command: List[str], cwd: str = None) -> Dict[str, Any]:
        """Execute shell command."""
        pass

    @abstractmethod
    def check_docker(self) -> bool:
        """Check if Docker is available."""
        pass


class RealActionRunner(ActionRunner):
    """Real implementation - actually does things."""

    def save_config(self, config: dict, path: str):
        import yaml
        with open(path, 'w') as f:
            yaml.dump(config, f)

    def run_shell(self, command: List[str], cwd: str = None):
        import subprocess
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
        return {
            'stdout': result.stdout,
            'stderr': result.stderr,
            'returncode': result.returncode
        }

    def check_docker(self) -> bool:
        result = self.run_shell(['docker', '--version'])
        return result['returncode'] == 0


class MockActionRunner(ActionRunner):
    """Mock for testing - records calls."""

    def __init__(self):
        self.calls = []
        self.responses = {}

    def save_config(self, config: dict, path: str):
        self.calls.append(('save_config', config, path))

    def run_shell(self, command: List[str], cwd: str = None):
        self.calls.append(('run_shell', command, cwd))
        return self.responses.get('run_shell', {
            'stdout': '', 'stderr': '', 'returncode': 0
        })

    def check_docker(self) -> bool:
        self.calls.append(('check_docker',))
        return self.responses.get('check_docker', True)
