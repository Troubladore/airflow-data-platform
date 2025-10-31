"""Kerberos auto-detection capabilities for corporate environments."""

import os
import subprocess
import re
from typing import Dict, Any, Optional, Tuple


class KerberosDetector:
    """Detect Kerberos configuration from the system environment."""

    def __init__(self, runner=None):
        """Initialize detector with optional runner for testing.

        Args:
            runner: Optional ActionRunner for executing commands
        """
        self.runner = runner
        self._cache = {}

    def run_command(self, cmd: list) -> Dict[str, Any]:
        """Execute a command and return result.

        Args:
            cmd: Command to execute as list

        Returns:
            Dict with returncode, stdout, stderr
        """
        if self.runner:
            return self.runner.run_shell(cmd)
        else:
            # Direct subprocess execution for standalone use
            try:
                result = subprocess.run(
                    cmd,
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                return {
                    'returncode': result.returncode,
                    'stdout': result.stdout,
                    'stderr': result.stderr
                }
            except subprocess.TimeoutExpired:
                return {'returncode': 1, 'stdout': '', 'stderr': 'Command timed out'}
            except Exception as e:
                return {'returncode': 1, 'stdout': '', 'stderr': str(e)}

    def detect_domain(self) -> Optional[str]:
        """Auto-detect Kerberos domain from various sources.

        Tries in order:
        1. Kerberos ticket cache (klist)
        2. Environment variable (USERDNSDOMAIN)
        3. PowerShell (WSL2 on Windows)
        4. krb5.conf file
        5. /etc/resolv.conf search domain

        Returns:
            Detected domain in uppercase or None
        """
        if 'domain' in self._cache:
            return self._cache['domain']

        domain = None

        # 1. Try to get from existing Kerberos tickets
        klist_domain = self._detect_from_klist()
        if klist_domain:
            domain = klist_domain

        # 2. Check environment variable (common in corp environments)
        if not domain:
            env_domain = os.environ.get('USERDNSDOMAIN', '').strip()
            if env_domain:
                domain = env_domain.upper()

        # 3. Try PowerShell if in WSL2
        if not domain and self._is_wsl2():
            ps_domain = self._detect_from_powershell()
            if ps_domain:
                domain = ps_domain

        # 4. Check krb5.conf
        if not domain:
            krb_domain = self._detect_from_krb5_conf()
            if krb_domain:
                domain = krb_domain

        # 5. Try resolv.conf as last resort
        if not domain:
            resolv_domain = self._detect_from_resolv_conf()
            if resolv_domain:
                domain = resolv_domain

        if domain:
            self._cache['domain'] = domain.upper()
            return domain.upper()

        return None

    def detect_ticket_cache(self) -> Optional[Dict[str, str]]:
        """Auto-detect Kerberos ticket cache location and format.

        Returns:
            Dict with 'path' and 'format' keys, or None
        """
        if 'ticket_cache' in self._cache:
            return self._cache['ticket_cache']

        # Run klist to get ticket cache info
        result = self.run_command(['klist'])
        if result['returncode'] != 0:
            # No klist or no tickets
            return None

        output = result['stdout']

        # Parse ticket cache line
        cache_match = re.search(r'Ticket cache:\s*(.+)', output)
        if not cache_match:
            return None

        cache_str = cache_match.group(1).strip()

        # Determine format and extract path
        ticket_info = {}

        if cache_str.startswith('FILE:'):
            # FILE format: FILE:/tmp/krb5cc_1000
            ticket_info['format'] = 'FILE'
            ticket_info['path'] = cache_str[5:]
            ticket_info['directory'] = os.path.dirname(cache_str[5:])

        elif cache_str.startswith('DIR::'):
            # DIR format: DIR::/home/user/.krb5-cache/dev/tkt
            ticket_info['format'] = 'DIR'
            full_path = cache_str[5:]

            # Detect base directory (parent of collection)
            if os.path.isfile(full_path):
                # Path includes ticket file
                parent = os.path.dirname(full_path)
                ticket_info['directory'] = os.path.dirname(parent)
            elif os.path.isdir(full_path):
                # Path is the collection directory
                ticket_info['directory'] = full_path
            else:
                return None

            ticket_info['path'] = full_path

        elif cache_str.startswith('KCM:'):
            # Kernel Credential Cache - needs special handling
            ticket_info['format'] = 'KCM'
            ticket_info['path'] = cache_str
            ticket_info['directory'] = None  # KCM doesn't use filesystem

        else:
            # Assume plain file path
            ticket_info['format'] = 'FILE'
            ticket_info['path'] = cache_str
            ticket_info['directory'] = os.path.dirname(cache_str)

        # Verify the path exists (except for KCM)
        if ticket_info['format'] != 'KCM':
            if not os.path.exists(ticket_info['path']):
                return None

        self._cache['ticket_cache'] = ticket_info
        return ticket_info

    def detect_principal(self) -> Optional[str]:
        """Auto-detect Kerberos principal from tickets.

        Returns:
            Principal string (e.g., user@DOMAIN.COM) or None
        """
        if 'principal' in self._cache:
            return self._cache['principal']

        result = self.run_command(['klist'])
        if result['returncode'] != 0:
            return None

        # Parse default principal line
        match = re.search(r'Default principal:\s*(.+)', result['stdout'])
        if match:
            principal = match.group(1).strip()
            self._cache['principal'] = principal
            return principal

        return None

    def detect_all(self) -> Dict[str, Any]:
        """Detect all Kerberos configuration.

        Returns:
            Dict with detected domain, ticket_cache, and principal
        """
        return {
            'domain': self.detect_domain(),
            'ticket_cache': self.detect_ticket_cache(),
            'principal': self.detect_principal(),
            'has_tickets': self._has_valid_tickets()
        }

    def _detect_from_klist(self) -> Optional[str]:
        """Extract domain from klist output."""
        result = self.run_command(['klist'])
        if result['returncode'] != 0:
            return None

        # Look for principal like user@DOMAIN.COM
        match = re.search(r'Default principal:\s*[^@]+@([A-Z.]+)', result['stdout'])
        if match:
            return match.group(1)

        return None

    def _detect_from_powershell(self) -> Optional[str]:
        """Detect domain using PowerShell (WSL2 on Windows)."""
        # Check if PowerShell is available
        ps_check = self.run_command(['which', 'powershell.exe'])
        if ps_check['returncode'] != 0:
            return None

        # Try to get computer domain
        ps_cmd = [
            'powershell.exe', '-Command',
            '([System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()).Name'
        ]
        result = self.run_command(ps_cmd)

        if result['returncode'] == 0:
            domain = result['stdout'].strip()
            # Check for errors in output
            if domain and 'Exception' not in domain:
                return domain.upper()

        # Fallback to environment variable via PowerShell
        ps_cmd = ['powershell.exe', '-Command', '$env:USERDNSDOMAIN']
        result = self.run_command(ps_cmd)

        if result['returncode'] == 0:
            domain = result['stdout'].strip()
            if domain:
                return domain.upper()

        return None

    def _detect_from_krb5_conf(self) -> Optional[str]:
        """Extract default realm from krb5.conf."""
        krb5_paths = [
            '/etc/krb5.conf',
            '/usr/local/etc/krb5.conf',
            os.path.expanduser('~/.krb5/krb5.conf')
        ]

        # Check KRB5_CONFIG environment variable
        if 'KRB5_CONFIG' in os.environ:
            krb5_paths.insert(0, os.environ['KRB5_CONFIG'])

        for path in krb5_paths:
            if os.path.exists(path):
                try:
                    with open(path, 'r') as f:
                        content = f.read()
                        # Look for default_realm
                        match = re.search(r'default_realm\s*=\s*([A-Z.]+)', content)
                        if match:
                            return match.group(1)
                except Exception:
                    continue

        return None

    def _detect_from_resolv_conf(self) -> Optional[str]:
        """Extract domain from /etc/resolv.conf search line."""
        if not os.path.exists('/etc/resolv.conf'):
            return None

        try:
            with open('/etc/resolv.conf', 'r') as f:
                for line in f:
                    if line.startswith('search ') or line.startswith('domain '):
                        parts = line.split()
                        if len(parts) > 1:
                            # Convert to uppercase Kerberos realm format
                            return parts[1].upper()
        except Exception:
            pass

        return None

    def _is_wsl2(self) -> bool:
        """Check if running in WSL2."""
        return os.path.exists('/proc/sys/fs/binfmt_misc/WSLInterop')

    def _has_valid_tickets(self) -> bool:
        """Check if there are valid Kerberos tickets."""
        result = self.run_command(['klist', '-s'])
        return result['returncode'] == 0

    def get_diagnostic_info(self) -> Dict[str, Any]:
        """Get comprehensive diagnostic information.

        Returns:
            Dict with all detected values and diagnostic details
        """
        info = {
            'detection': self.detect_all(),
            'environment': {
                'is_wsl2': self._is_wsl2(),
                'has_klist': self.run_command(['which', 'klist'])['returncode'] == 0,
                'has_kinit': self.run_command(['which', 'kinit'])['returncode'] == 0,
                'krb5_config': os.environ.get('KRB5_CONFIG'),
                'krb5ccname': os.environ.get('KRB5CCNAME'),
                'userdnsdomain': os.environ.get('USERDNSDOMAIN'),
            },
            'suggestions': self._get_suggestions()
        }

        return info

    def _get_suggestions(self) -> Dict[str, str]:
        """Get suggestions based on detected configuration."""
        suggestions = {}
        detection = self.detect_all()

        if not detection['domain']:
            suggestions['domain'] = (
                "Could not auto-detect domain. "
                "Please enter your Kerberos realm (e.g., COMPANY.COM)"
            )

        if not detection['has_tickets']:
            if detection['domain']:
                suggestions['tickets'] = (
                    f"No valid tickets found. Run: kinit YOUR_USERNAME@{detection['domain']}"
                )
            else:
                suggestions['tickets'] = (
                    "No valid tickets found. Run: kinit YOUR_USERNAME@YOUR_DOMAIN.COM"
                )

        if detection['ticket_cache'] and detection['ticket_cache']['format'] == 'KCM':
            suggestions['cache_format'] = (
                "KCM ticket format detected. For Docker compatibility, "
                "consider switching to FILE format:\n"
                "export KRB5CCNAME=FILE:/tmp/krb5cc_$(id -u)"
            )

        return suggestions