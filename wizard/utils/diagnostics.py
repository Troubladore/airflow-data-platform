"""Diagnostic utilities for service failures.

Provides automatic diagnostics when services fail to start,
capturing context, generating summaries, and saving detailed logs.
"""

import os
import json
from datetime import datetime
from typing import Dict, Any, List, Optional


class DiagnosticCollector:
    """Collects and manages diagnostic information for service failures."""

    def __init__(self):
        self.failures = []
        self.start_time = datetime.now()

    def record_failure(self, service: str, phase: str, error: str,
                      context: Optional[Dict[str, Any]] = None) -> None:
        """Record a service failure with context.

        Args:
            service: Name of the service that failed (postgres, kerberos, pagila)
            phase: Phase where failure occurred (pull_image, docker_compose_up, etc)
            error: Error message or description
            context: Additional context (image name, command, etc)
        """
        self.failures.append({
            'service': service,
            'phase': phase,
            'error': error,
            'context': context or {},
            'timestamp': datetime.now().isoformat()
        })

    def get_summary(self) -> str:
        """Generate human-readable summary of failures."""
        if not self.failures:
            return "No failures recorded"

        lines = [f"{len(self.failures)} service failures detected:"]
        lines.append("")

        for failure in self.failures:
            lines.append(f"• {failure['service']} failed at: {failure['phase']}")
            lines.append(f"  Error: {failure['error']}")

        return "\n".join(lines)

    def save_log(self, directory: str = ".") -> str:
        """Save detailed diagnostics to timestamped log file.

        Returns:
            Path to the saved log file
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_path = os.path.join(directory, f"diagnostic_{timestamp}.log")

        with open(log_path, 'w') as f:
            f.write(f"Platform Setup Diagnostics\n")
            f.write(f"Generated: {datetime.now()}\n")
            f.write("=" * 70 + "\n\n")

            for i, failure in enumerate(self.failures, 1):
                f.write(f"FAILURE {i}: {failure['service'].upper()}\n")
                f.write("-" * 40 + "\n")
                f.write(f"Phase: {failure['phase']}\n")
                f.write(f"Error: {failure['error']}\n")
                f.write(f"Timestamp: {failure['timestamp']}\n")

                if failure['context']:
                    f.write("\nContext:\n")
                    for key, value in failure['context'].items():
                        f.write(f"  {key}: {value}\n")

                f.write("\n")

        return log_path


class ServiceDiagnostics:
    """Run service-specific diagnostics."""

    def __init__(self, runner):
        self.runner = runner

    def diagnose_postgres_failure(self, ctx: Dict[str, Any]) -> Dict[str, Any]:
        """Diagnose PostgreSQL startup failure.

        Returns diagnostic information including:
        - container_exists: Whether container was created
        - diagnosis: Human-readable diagnosis
        - suggestions: Next steps to resolve
        """
        result = {
            'container_exists': False,
            'diagnosis': '',
            'suggestions': []
        }

        # Check if container exists
        container_check = self.runner.run_shell(['docker', 'ps', '-a', '--format', '{{.Names}}'])
        if 'platform-postgres' in container_check.get('stdout', ''):
            result['container_exists'] = True
            result['diagnosis'] = 'Container created but failed to start'

            # Get container logs
            logs = self.runner.run_shell(['docker', 'logs', 'platform-postgres', '--tail', '20'])
            if 'permission denied' in logs.get('stderr', '').lower():
                result['suggestions'].append('Check file permissions')
        else:
            result['container_exists'] = False
            result['diagnosis'] = 'Container never created - Docker Compose failed'

            image = ctx.get('services.postgres.image', 'postgres:17.5-alpine')
            if '/' in image.split(':')[0]:
                result['suggestions'].append(f'Try: docker pull {image}')
                result['suggestions'].append(f'May need: docker login {image.split("/")[0]}')

        return result

    def diagnose_kerberos_failure(self, ctx: Dict[str, Any]) -> Dict[str, Any]:
        """Diagnose Kerberos startup failure."""
        result = {
            'using_prebuilt': ctx.get('services.kerberos.use_prebuilt', False),
            'diagnosis': '',
            'notes': []
        }

        if result['using_prebuilt']:
            result['notes'].append('Prebuilt image expected - should not install packages')
            image = ctx.get('services.kerberos.image', '')
            if image and '/' in image:
                result['diagnosis'] = 'Corporate prebuilt image may not be accessible'

        # Check container
        container_check = self.runner.run_shell(['docker', 'ps', '-a', '--format', '{{.Names}}'])
        if 'kerberos-sidecar-mock' not in container_check.get('stdout', ''):
            result['diagnosis'] = 'Kerberos container not created'

        return result

    def diagnose_pagila_failure(self, ctx: Dict[str, Any]) -> Dict[str, Any]:
        """Diagnose Pagila setup failure."""
        result = {
            'repo_cloned': False,
            'diagnosis': '',
            'suggestions': []
        }

        # Check if pagila directory exists
        dir_check = self.runner.run_shell(['test', '-d', '../pagila'])
        if dir_check.get('returncode') == 0:
            result['repo_cloned'] = True
            result['diagnosis'] = 'Repository cloned but Docker setup failed'
        else:
            result['repo_cloned'] = False
            result['diagnosis'] = 'Git clone may have failed'
            result['suggestions'].append(f'Check network access to {ctx.get("services.pagila.repo_url", "repo")}')

        return result


def create_diagnostic_summary(failures: List[Dict], log_file: str) -> str:
    """Create user-friendly summary with clear next steps.

    Args:
        failures: List of failure records
        log_file: Path to detailed log file

    Returns:
        Formatted summary for display to user
    """
    lines = []
    lines.append("\n🔴 SETUP FAILED\n")
    lines.append("What happened:")

    for failure in failures:
        lines.append(f"  • {failure['service']} - {failure.get('diagnosis', failure.get('error', 'Unknown error'))}")

    lines.append("\nNext steps:")

    # Add specific remediation steps based on error patterns
    for failure in failures:
        if 'pull access denied' in failure.get('error', ''):
            lines.append(f"  1. Run: docker login {failure.get('service', 'registry')}")
        elif 'manifest unknown' in failure.get('error', ''):
            lines.append(f"  1. Verify image name and tag are correct")
        elif 'address already in use' in failure.get('error', ''):
            lines.append(f"  1. Check port usage: lsof -i :5432")

    lines.append(f"\nFull details saved to: {log_file}")
    lines.append("View with: cat " + log_file)

    return "\n".join(lines)