"""PostgreSQL connector with Kerberos support.

Provides PostgreSQL connectivity with optional Kerberos authentication,
critical for containerized environments where username extraction from
tickets is required.
"""

import subprocess
from typing import Any, Optional

import psycopg2
from pydantic import Field

from .base import BaseConnector, ConnectorConfig


class PostgresConfig(ConnectorConfig):
    """PostgreSQL-specific configuration.

    Extends base configuration with PostgreSQL-specific settings
    including Kerberos authentication support.
    """

    port: int = 5432
    use_kerberos: bool = False
    gssencmode: str = Field(default="prefer", description="GSSAPI encryption mode")
    krb5_ccname: Optional[str] = Field(default=None, description="Kerberos credential cache")


class PostgresConnector(BaseConnector):
    """PostgreSQL connector with Kerberos support.

    Handles PostgreSQL connections with optional Kerberos authentication.
    Critical for containers running as root that need to extract username
    from Kerberos tickets.
    """

    def __init__(self, config: PostgresConfig):
        """Initialize PostgreSQL connector.

        Args:
            config: PostgresConfig with connection parameters
        """
        super().__init__(config)
        self.config: PostgresConfig = config

    def _get_kerberos_username(self) -> Optional[str]:
        """Extract username from Kerberos ticket.

        CRITICAL: Container runs as root, must specify user from ticket.

        Returns:
            Username extracted from Kerberos principal, or None if unavailable
        """
        try:
            result = subprocess.run(['klist'], capture_output=True, text=True)
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if 'Default principal:' in line:
                        principal = line.split(':')[1].strip()
                        return principal.split('@')[0]
        except Exception:
            # klist not available or other error
            pass
        return None

    def test_connection(self) -> bool:
        """Test PostgreSQL connection.

        Returns:
            True if connection successful, False otherwise
        """
        try:
            conn = self.get_connection()
            conn.close()
            return True
        except Exception:
            return False

    def get_connection(self) -> Any:
        """Get PostgreSQL connection with optional Kerberos auth.

        Returns:
            psycopg2 connection object

        Raises:
            psycopg2.Error: If connection fails
        """
        conn_params = {
            'host': self.config.host,
            'port': self.config.port,
            'database': self.config.database
        }

        if self.config.use_kerberos:
            # CRITICAL: Container runs as root, must specify user from ticket
            username = self._get_kerberos_username()
            if username:
                conn_params['user'] = username
            conn_params['gssencmode'] = self.config.gssencmode

            # Set credential cache if specified
            if self.config.krb5_ccname:
                import os
                os.environ['KRB5CCNAME'] = self.config.krb5_ccname
        else:
            # Standard auth (username/password to be added by developer as needed)
            pass

        return psycopg2.connect(**conn_params)

    def get_tables(self, schema: Optional[str] = 'public') -> list[str]:
        """List tables in schema.

        Args:
            schema: Schema name (default: 'public')

        Returns:
            List of table names in the schema
        """
        with self.connection_context() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT table_name
                    FROM information_schema.tables
                    WHERE table_schema = %s
                    ORDER BY table_name
                """, (schema,))
                return [row[0] for row in cur.fetchall()]