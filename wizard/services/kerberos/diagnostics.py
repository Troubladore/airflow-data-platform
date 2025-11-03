"""Kerberos diagnostic utilities for connection troubleshooting."""

import os
import re
from typing import Dict, Any, List


def parse_krb5_config() -> Dict[str, Any]:
    """Parse krb5.conf for diagnostic information.

    Returns:
        Dictionary containing parsed krb5.conf sections
    """
    config = {}
    krb5_path = '/etc/krb5.conf'

    if not os.path.exists(krb5_path):
        return config

    try:
        with open(krb5_path, 'r') as f:
            content = f.read()

        # Parse default realm
        realm_match = re.search(r'default_realm\s*=\s*(\S+)', content)
        if realm_match:
            config['default_realm'] = realm_match.group(1)

        # Parse realms section
        realms_section = re.search(r'\[realms\](.*?)(?:\[|$)', content, re.DOTALL)
        if realms_section:
            config['realms'] = {}
            realm_blocks = re.findall(r'(\S+)\s*=\s*\{([^}]+)\}', realms_section.group(1))

            for realm_name, realm_content in realm_blocks:
                realm_config = {}

                # Extract KDCs
                kdcs = re.findall(r'kdc\s*=\s*(\S+)', realm_content)
                if kdcs:
                    realm_config['kdc'] = kdcs

                # Extract admin server
                admin_match = re.search(r'admin_server\s*=\s*(\S+)', realm_content)
                if admin_match:
                    realm_config['admin_server'] = admin_match.group(1)

                config['realms'][realm_name] = realm_config

        # Parse domain_realm section
        domain_section = re.search(r'\[domain_realm\](.*?)(?:\[|$)', content, re.DOTALL)
        if domain_section:
            config['domain_realm'] = {}
            mappings = re.findall(r'(\S+)\s*=\s*(\S+)', domain_section.group(1))
            for domain, realm in mappings:
                config['domain_realm'][domain] = realm

        # Parse libdefaults for additional settings
        libdefaults = re.search(r'\[libdefaults\](.*?)(?:\[|$)', content, re.DOTALL)
        if libdefaults:
            # Extract ticket lifetime
            lifetime_match = re.search(r'ticket_lifetime\s*=\s*(\S+)', libdefaults.group(1))
            if lifetime_match:
                config['ticket_lifetime'] = lifetime_match.group(1)

            # Extract encryption types
            enctypes_match = re.search(r'default_tgs_enctypes\s*=\s*([^\n]+)', libdefaults.group(1))
            if enctypes_match:
                config['encryption_types'] = enctypes_match.group(1).strip()

    except Exception as e:
        config['parse_error'] = str(e)

    return config


def parse_ticket_status(klist_result: Dict[str, Any]) -> str:
    """Parse klist output to determine ticket status.

    Args:
        klist_result: Result from running klist command

    Returns:
        Human-readable ticket status
    """
    if klist_result.get('returncode') != 0:
        stderr = klist_result.get('stderr', '')
        if 'No credentials cache found' in stderr or 'not found' in stderr.lower():
            return "No Kerberos tickets found"
        return f"Unable to check tickets: {stderr}"

    stdout = klist_result.get('stdout', '')

    # Look for principal
    principal_match = re.search(r'Default principal:\s*(\S+)', stdout)
    if not principal_match:
        return "No valid tickets"

    principal = principal_match.group(1)

    # Check for valid tickets
    if 'krbtgt' in stdout:
        # Look for expiry
        if 'Expires' in stdout:
            return f"Active tickets for {principal}"
        return f"Tickets present for {principal} (status unknown)"

    return f"No valid tickets for {principal}"


def check_dns_resolution(fqdn: str, runner) -> Dict[str, Any]:
    """Check DNS resolution for a given FQDN.

    Args:
        fqdn: Fully qualified domain name to check
        runner: Action runner for executing commands

    Returns:
        Dictionary with DNS check results
    """
    result = {'fqdn': fqdn, 'resolved': False, 'addresses': []}

    # Try nslookup
    dns_result = runner.run_shell(['nslookup', fqdn])

    if dns_result.get('returncode') == 0:
        output = dns_result.get('stdout', '')
        # Extract IP addresses
        addresses = re.findall(r'Address:\s*(\d+\.\d+\.\d+\.\d+)', output)
        if addresses:
            result['resolved'] = True
            result['addresses'] = addresses
    else:
        # Try host command as fallback
        host_result = runner.run_shell(['host', fqdn])
        if host_result.get('returncode') == 0:
            output = host_result.get('stdout', '')
            addresses = re.findall(r'has address\s+(\d+\.\d+\.\d+\.\d+)', output)
            if addresses:
                result['resolved'] = True
                result['addresses'] = addresses

    return result


def check_network_connectivity(host: str, port: int, runner) -> bool:
    """Check if a port is reachable on a host.

    Args:
        host: Hostname or IP address
        port: Port number to check
        runner: Action runner

    Returns:
        True if port is reachable
    """
    # Use nc (netcat) for port checking
    result = runner.run_shell(['nc', '-zv', '-w', '2', host, str(port)])
    return result.get('returncode') == 0


def validate_spn_format(spn: str) -> Dict[str, Any]:
    """Validate Service Principal Name format.

    Args:
        spn: Service Principal Name to validate

    Returns:
        Dictionary with validation results
    """
    validation = {'valid': False, 'service': None, 'host': None, 'issues': []}

    # SPN format: service/host[@realm]
    spn_pattern = r'^([^/]+)/([^@]+)(?:@(.+))?$'
    match = re.match(spn_pattern, spn)

    if match:
        validation['valid'] = True
        validation['service'] = match.group(1)
        validation['host'] = match.group(2)
        if match.group(3):
            validation['realm'] = match.group(3)
    else:
        validation['issues'].append('Invalid SPN format. Expected: service/host[@realm]')

    return validation


def run_extended_diagnostics(ctx: Dict[str, Any], runner) -> Dict[str, Any]:
    """Run comprehensive diagnostic checks for Kerberos issues.

    Args:
        ctx: Context with configuration
        runner: Action runner

    Returns:
        Dictionary with diagnostic results
    """
    diagnostics = {
        'krb5_config': {},
        'tickets': {},
        'dns': {},
        'network': {},
        'configuration_issues': []
    }

    # Parse krb5.conf
    krb5_config = parse_krb5_config()
    diagnostics['krb5_config'] = krb5_config

    # Check for realm mismatch
    configured_domain = ctx.get('services.kerberos.domain', '').upper()
    default_realm = krb5_config.get('default_realm', '').upper()

    if configured_domain and default_realm and configured_domain != default_realm:
        diagnostics['configuration_issues'].append(
            f"Realm mismatch: Configured domain '{configured_domain}' doesn't match "
            f"krb5.conf default_realm '{default_realm}'"
        )
        diagnostics['realm_mismatch'] = True

    # Check Kerberos tickets
    klist_result = runner.run_shell(['klist'])
    diagnostics['tickets']['status'] = parse_ticket_status(klist_result)

    # DNS checks for SQL Server if configured
    sql_fqdn = ctx.get('services.kerberos.sql_server_fqdn')
    if sql_fqdn:
        diagnostics['dns']['sql_server'] = check_dns_resolution(sql_fqdn, runner)
        if diagnostics['dns']['sql_server']['resolved']:
            # Check SQL Server port
            for addr in diagnostics['dns']['sql_server']['addresses']:
                if check_network_connectivity(addr, 1433, runner):
                    diagnostics['network']['sql_server_reachable'] = True
                    break

    # DNS checks for PostgreSQL if configured
    pg_fqdn = ctx.get('services.kerberos.postgres_fqdn')
    if pg_fqdn:
        diagnostics['dns']['postgres'] = check_dns_resolution(pg_fqdn, runner)
        if diagnostics['dns']['postgres']['resolved']:
            # Check PostgreSQL port
            for addr in diagnostics['dns']['postgres']['addresses']:
                if check_network_connectivity(addr, 5432, runner):
                    diagnostics['network']['postgres_reachable'] = True
                    break

    # Check KDC reachability if configured
    if 'realms' in krb5_config and configured_domain in krb5_config['realms']:
        realm_config = krb5_config['realms'][configured_domain]
        kdcs = realm_config.get('kdc', [])
        for kdc in kdcs:
            # KDCs might have port specified (kdc:88)
            kdc_host = kdc.split(':')[0]
            dns_result = check_dns_resolution(kdc_host, runner)
            if dns_result['resolved']:
                diagnostics['dns'][f'kdc_{kdc_host}'] = dns_result
                # Check Kerberos port (88)
                for addr in dns_result['addresses']:
                    if check_network_connectivity(addr, 88, runner):
                        diagnostics['network'][f'kdc_{kdc_host}_reachable'] = True
                        break

    # Display diagnostic summary
    runner.display("\n" + "=" * 60)
    runner.display("EXTENDED KERBEROS DIAGNOSTICS")
    runner.display("=" * 60)

    # Display krb5.conf status
    runner.display("\n📋 Kerberos Configuration (krb5.conf):")
    if krb5_config:
        runner.display(f"  Default Realm: {krb5_config.get('default_realm', 'Not set')}")
        if 'realms' in krb5_config:
            runner.display(f"  Configured Realms: {', '.join(krb5_config['realms'].keys())}")
        if 'ticket_lifetime' in krb5_config:
            runner.display(f"  Ticket Lifetime: {krb5_config['ticket_lifetime']}")
    else:
        runner.display("  ⚠️  No krb5.conf found or unable to parse")

    # Display ticket status
    runner.display(f"\n🎫 Ticket Status:")
    runner.display(f"  {diagnostics['tickets']['status']}")

    # Display DNS results
    if diagnostics['dns']:
        runner.display("\n🌐 DNS Resolution:")
        for service, dns_info in diagnostics['dns'].items():
            if isinstance(dns_info, dict) and 'fqdn' in dns_info:
                status = "✅" if dns_info['resolved'] else "❌"
                runner.display(f"  {status} {dns_info['fqdn']}: {', '.join(dns_info.get('addresses', ['Not resolved']))}")

    # Display network connectivity
    if diagnostics['network']:
        runner.display("\n🔌 Network Connectivity:")
        for service, reachable in diagnostics['network'].items():
            status = "✅" if reachable else "❌"
            service_name = service.replace('_reachable', '').replace('_', ' ').title()
            runner.display(f"  {status} {service_name}")

    # Display configuration issues
    if diagnostics['configuration_issues']:
        runner.display("\n⚠️  Configuration Issues:")
        for issue in diagnostics['configuration_issues']:
            runner.display(f"  • {issue}")

    runner.display("\n" + "=" * 60)

    return diagnostics