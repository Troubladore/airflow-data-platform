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

    @abstractmethod
    def file_exists(self, path: str) -> bool:
        """Check if file exists at given path."""
        pass

    @abstractmethod
    def display(self, message: str) -> None:
        """Display a message to the user.

        Args:
            message: Text to display (may contain newlines)
        """
        pass

    @abstractmethod
    def get_input(self, prompt: str, default: str = None) -> str:
        """Get input from user.

        Args:
            prompt: Question to ask user
            default: Default value if user presses Enter (shown in [brackets])

        Returns:
            User's input string (or default if empty)
        """
        pass

    @abstractmethod
    def write_file(self, path: str, content: str) -> None:
        """Write content to a file.

        Args:
            path: Path to file to write
            content: Content to write to file
        """
        pass


class RealActionRunner(ActionRunner):
    """Real implementation - actually does things."""

    def __init__(self, verbose: bool = False):
        """Initialize with optional verbose mode.

        Args:
            verbose: If True, show command output in real-time
        """
        self.verbose = verbose
        # Check for verbose environment variable as well
        import os
        if os.environ.get('WIZARD_VERBOSE'):
            self.verbose = True

    def save_config(self, config: dict, path: str):
        import yaml
        import os

        # Read existing config if file exists
        existing_config = {}
        if os.path.exists(path):
            with open(path, 'r') as f:
                existing_config = yaml.safe_load(f) or {}

        # Deep merge: update existing config with new values
        merged_config = self._deep_merge(existing_config, config)

        # Check if all services are disabled
        all_services_disabled = self._all_services_disabled(merged_config)

        if all_services_disabled:
            # Delete the file if all services are disabled
            if os.path.exists(path):
                os.remove(path)
        else:
            # Save the merged config
            with open(path, 'w') as f:
                yaml.dump(merged_config, f)

    def _deep_merge(self, base: dict, update: dict) -> dict:
        """Deep merge update dict into base dict.

        Args:
            base: Base dictionary
            update: Dictionary with updates to merge

        Returns:
            Merged dictionary
        """
        result = base.copy()

        for key, value in update.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                # Recursively merge nested dictionaries
                result[key] = self._deep_merge(result[key], value)
            else:
                # Overwrite with new value
                result[key] = value

        return result

    def _all_services_disabled(self, config: dict) -> bool:
        """Check if all services in config are disabled.

        Args:
            config: Configuration dictionary

        Returns:
            True if all services are disabled, False otherwise
        """
        if 'services' not in config:
            return True

        services = config['services']
        if not services:
            return True

        # Check if all services have enabled=False
        for service_name, service_config in services.items():
            if isinstance(service_config, dict):
                # If enabled is not present or is True, service is enabled
                if service_config.get('enabled', True):
                    return False

        # All services are disabled
        return True

    def run_shell(self, command: List[str], cwd: str = None):
        import subprocess
        import os
        import platform

        # Detect WSL2 environment
        is_wsl = False
        if platform.system() == 'Linux':
            # Check if running under WSL
            if os.path.exists('/proc/version'):
                with open('/proc/version', 'r') as f:
                    if 'microsoft' in f.read().lower():
                        is_wsl = True

        # Log command execution in verbose mode
        if self.verbose:
            print(f"[VERBOSE] Running command: {' '.join(command)}")
            if is_wsl:
                print("[VERBOSE] WSL2 environment detected")
            if cwd:
                print(f"[VERBOSE] Working directory: {cwd}")
            else:
                print(f"[VERBOSE] Working directory: {os.getcwd()}")

        # Special handling for 'make -C' commands
        if command[0] == 'make' and '-C' in command:
            # Find the directory argument after -C
            try:
                c_index = command.index('-C')
                if c_index + 1 < len(command):
                    target_dir = command[c_index + 1]

                    # Check if target directory exists
                    if not os.path.exists(target_dir):
                        error_msg = f"make -C target directory does not exist: {target_dir}"
                        if self.verbose:
                            print(f"[VERBOSE] ERROR: {error_msg}")
                            print(f"[VERBOSE] Current directory: {os.getcwd()}")
                            print(f"[VERBOSE] Directory contents:")
                            try:
                                for item in os.listdir('.'):
                                    print(f"[VERBOSE]   - {item}")
                            except:
                                pass

                        return {
                            'stdout': '',
                            'stderr': f"make: *** {target_dir}: No such file or directory.  Stop.",
                            'returncode': 2
                        }

                    # In WSL2, convert Windows paths if needed
                    if is_wsl and target_dir.startswith('/mnt/'):
                        if self.verbose:
                            print(f"[VERBOSE] WSL2: Converting Windows path: {target_dir}")
            except (ValueError, IndexError):
                pass

        try:
            if self.verbose:
                # In verbose mode, show output in real-time
                result = subprocess.run(
                    command,
                    cwd=cwd,
                    text=True,
                    capture_output=False,  # Don't capture, let it flow to terminal
                    stdout=None,  # Inherit stdout
                    stderr=None   # Inherit stderr
                )
                # For compatibility, still return empty strings for output
                return {
                    'stdout': '',
                    'stderr': '',
                    'returncode': result.returncode
                }
            else:
                # Normal mode: capture output silently
                result = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
                return {
                    'stdout': result.stdout,
                    'stderr': result.stderr,
                    'returncode': result.returncode
                }
        except FileNotFoundError as e:
            # This is likely the "No such file or directory" error
            error_msg = f"FileNotFoundError: {str(e)}"
            if self.verbose:
                print(f"[VERBOSE] ERROR: {error_msg}")
                print(f"[VERBOSE] Command not found or path issue: {command[0]}")
                print(f"[VERBOSE] Current working directory: {os.getcwd()}")
                if cwd:
                    print(f"[VERBOSE] Attempted to run in: {cwd}")
                    print(f"[VERBOSE] Does that directory exist? {os.path.exists(cwd)}")

            return {
                'stdout': '',
                'stderr': error_msg,
                'returncode': 127  # Standard "command not found" exit code
            }
        except Exception as e:
            # Catch any other exceptions
            error_msg = f"{type(e).__name__}: {str(e)}"
            if self.verbose:
                print(f"[VERBOSE] UNEXPECTED ERROR: {error_msg}")

            return {
                'stdout': '',
                'stderr': error_msg,
                'returncode': 1
            }

    def check_docker(self) -> bool:
        result = self.run_shell(['docker', '--version'])
        return result['returncode'] == 0

    def file_exists(self, path: str) -> bool:
        import os
        return os.path.exists(path)

    def display(self, message: str) -> None:
        """Print message to stdout."""
        print(message)

    def get_input(self, prompt: str, default: str = None) -> str:
        """Read from stdin with optional default."""
        # Format default for display
        if default is not None:
            # Special formatting for boolean defaults
            if isinstance(default, bool):
                default_display = 'y/N' if not default else 'Y/n'
            else:
                default_display = str(default)

            full_prompt = f"{prompt} [{default_display}]: "
            response = input(full_prompt).strip()
            print()  # Add newline after user input

            # Return response or default
            if response:
                return response
            else:
                return str(default) if not isinstance(default, bool) else default
        else:
            # No default
            full_prompt = f"{prompt}: "
            response = input(full_prompt).strip()
            print()  # Add newline after user input
            return response

    def write_file(self, path: str, content: str) -> None:
        """Write content to a file."""
        with open(path, 'w') as f:
            f.write(content)


class MockActionRunner(ActionRunner):
    """Mock for testing - records calls."""

    def __init__(self):
        self.calls = []
        self.responses = {}
        self.input_queue = []  # Pre-scripted user inputs for testing

    def save_config(self, config: dict, path: str):
        self.calls.append(('save_config', config, path))

    def run_shell(self, command: List[str], cwd: str = None):
        self.calls.append(('run_shell', command, cwd))

        # Support tuple-based command matching for discovery tests
        if 'run_shell' in self.responses:
            response_dict = self.responses['run_shell']

            # Check if responses is a dict with tuple keys (command matching)
            if isinstance(response_dict, dict):
                # Try exact tuple match first
                command_tuple = tuple(command)
                if command_tuple in response_dict:
                    # Return the dict directly if it's already a proper response
                    result = response_dict[command_tuple]
                    if isinstance(result, dict) and 'returncode' in result:
                        return result
                    # Otherwise wrap it as stdout (backward compatibility)
                    return {'stdout': result, 'stderr': '', 'returncode': 0}

            # Otherwise use as default response
            return response_dict

        # Default empty response
        return {'stdout': '', 'stderr': '', 'returncode': 0}

    def check_docker(self) -> bool:
        self.calls.append(('check_docker',))
        return self.responses.get('check_docker', True)

    def file_exists(self, path: str) -> bool:
        self.calls.append(('file_exists', path))
        return self.responses.get('file_exists', {}).get(path, False)

    def display(self, message: str) -> None:
        """Capture display call for test verification."""
        self.calls.append(('display', message))

    def get_input(self, prompt: str, default: str = None) -> str:
        """Return next value from input_queue."""
        self.calls.append(('get_input', prompt, default))

        # Pop next scripted response
        if self.input_queue:
            response = self.input_queue.pop(0)
            # Match RealActionRunner: apply default if response is empty
            return response if response else (default if default else '')

        # Fall back to default or empty string
        return default if default else ''

    def write_file(self, path: str, content: str) -> None:
        """Record write_file call for test verification."""
        self.calls.append(('write_file', path, content))
