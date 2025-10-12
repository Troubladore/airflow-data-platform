"""
SQL Server Hook with Kerberos/NT Authentication Support
"""

import logging
import os
from contextlib import contextmanager
from typing import Any

import pyodbc
from airflow.hooks.base import BaseHook
from airflow.models import Connection
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)


class MSSQLKerberosHook(BaseHook):
    """
    Hook for SQL Server with Kerberos/NT Authentication support.

    This hook can connect using:
    1. Kerberos ticket cache (for NT Authentication)
    2. SQL Server authentication (username/password)
    3. Azure AD authentication

    Connection Configuration:
    - conn_id: Airflow connection ID
    - Connection type: mssql
    - Host: SQL Server hostname
    - Port: SQL Server port (default 1433)
    - Schema: Database name
    - Login/Password: For SQL auth (leave empty for Kerberos)
    - Extra: JSON with additional options:
        {
            "auth_type": "kerberos",  # or "sql", "azure_ad"
            "driver": "ODBC Driver 18 for SQL Server",
            "trust_server_certificate": true,
            "application_name": "Airflow",
            "connect_timeout": 30
        }
    """

    conn_name_attr = "mssql_conn_id"
    default_conn_name = "mssql_default"
    conn_type = "mssql"
    hook_name = "Microsoft SQL Server (Kerberos)"

    def __init__(self, mssql_conn_id: str = default_conn_name):
        super().__init__()
        self.mssql_conn_id = mssql_conn_id
        self.connection: Connection | None = None
        self.engine: Engine | None = None

    def get_conn(self) -> pyodbc.Connection:
        """Get ODBC connection to SQL Server."""
        if not self.connection:
            self.connection = self.get_connection(self.mssql_conn_id)

        conn_str = self._build_connection_string()
        logger.info(f"Connecting to SQL Server: {self.connection.host}")

        try:
            return pyodbc.connect(conn_str)
        except Exception as e:
            logger.error(f"Failed to connect to SQL Server: {e}")
            raise

    def get_sqlalchemy_engine(self, **kwargs) -> Engine:
        """Get SQLAlchemy engine for SQL Server."""
        if not self.engine:
            conn_url = self._build_sqlalchemy_url()
            self.engine = create_engine(conn_url, **kwargs)
        return self.engine

    @contextmanager
    def get_session(self) -> Session:
        """Get SQLAlchemy session context manager."""
        engine = self.get_sqlalchemy_engine()
        with Session(engine) as session:
            yield session

    def _build_connection_string(self) -> str:
        """Build ODBC connection string based on authentication type."""
        if not self.connection:
            self.connection = self.get_connection(self.mssql_conn_id)

        extra = self.connection.extra_dejson
        auth_type = extra.get("auth_type", "sql").lower()
        driver = extra.get("driver", "ODBC Driver 18 for SQL Server")

        # Base connection parameters
        conn_params = [
            f"DRIVER={{{driver}}}",
            f"SERVER={self.connection.host},{self.connection.port or 1433}",
            f"DATABASE={self.connection.schema or 'master'}",
        ]

        # Authentication-specific parameters
        if auth_type == "kerberos":
            # Kerberos/NT Authentication
            conn_params.extend(
                [
                    "Trusted_Connection=Yes",
                    "Authentication=Kerberos",
                ]
            )
            # Ensure Kerberos environment is set
            if "KRB5CCNAME" not in os.environ:
                logger.warning("KRB5CCNAME not set, using default: /krb5/cache/krb5cc")
                os.environ["KRB5CCNAME"] = "/krb5/cache/krb5cc"

        elif auth_type == "azure_ad":
            # Azure AD Authentication
            conn_params.extend(
                [
                    "Authentication=ActiveDirectoryIntegrated",
                ]
            )

        else:  # SQL Authentication
            if not self.connection.login:
                raise ValueError("SQL authentication requires username")
            conn_params.extend(
                [
                    f"UID={self.connection.login}",
                    f"PWD={self.connection.password or ''}",
                ]
            )

        # Additional options
        if extra.get("trust_server_certificate", False):
            conn_params.append("TrustServerCertificate=Yes")

        if extra.get("encrypt", True):
            conn_params.append("Encrypt=Yes")

        if "application_name" in extra:
            conn_params.append(f"APP={extra['application_name']}")

        if "connect_timeout" in extra:
            conn_params.append(f"Connection Timeout={extra['connect_timeout']}")

        return ";".join(conn_params)

    def _build_sqlalchemy_url(self) -> str:
        """Build SQLAlchemy URL for SQL Server."""
        conn_str = self._build_connection_string()
        # URL encode the connection string
        import urllib.parse

        encoded = urllib.parse.quote_plus(conn_str)
        return f"mssql+pyodbc:///?odbc_connect={encoded}"

    def test_connection(self) -> tuple[bool, str]:
        """Test the SQL Server connection."""
        try:
            conn = self.get_conn()
            cursor = conn.cursor()
            cursor.execute("SELECT @@VERSION")
            version = cursor.fetchone()[0]
            conn.close()
            return True, f"Connected successfully. Server version: {version[:50]}..."
        except Exception as e:
            return False, str(e)

    def run(self, sql: str, parameters: dict | None = None, autocommit: bool = False) -> list[Any]:
        """
        Execute SQL statement and return results.

        :param sql: SQL query to execute
        :param parameters: Parameters for the query
        :param autocommit: Whether to autocommit the transaction
        :return: Query results as list of tuples
        """
        conn = self.get_conn()
        if autocommit:
            conn.autocommit = True

        cursor = conn.cursor()

        try:
            if parameters:
                cursor.execute(sql, parameters)
            else:
                cursor.execute(sql)

            if cursor.description:
                results = cursor.fetchall()
            else:
                results = []

            if not autocommit:
                conn.commit()

            return results

        except Exception as e:
            if not autocommit:
                conn.rollback()
            raise e

        finally:
            cursor.close()
            conn.close()

    def bulk_insert(self, table: str, rows: list[tuple], commit_every: int = 1000) -> int:
        """
        Bulk insert rows into a table.

        :param table: Target table name
        :param rows: List of tuples containing row data
        :param commit_every: Commit after this many rows
        :return: Number of rows inserted
        """
        if not rows:
            return 0

        conn = self.get_conn()
        cursor = conn.cursor()
        cursor.fast_executemany = True

        # Build insert statement based on first row
        placeholders = ",".join(["?" for _ in rows[0]])
        sql = f"INSERT INTO {table} VALUES ({placeholders})"

        try:
            total_inserted = 0
            for i in range(0, len(rows), commit_every):
                batch = rows[i : i + commit_every]
                cursor.executemany(sql, batch)
                conn.commit()
                total_inserted += len(batch)
                logger.info(f"Inserted {total_inserted}/{len(rows)} rows")

            return total_inserted

        except Exception as e:
            conn.rollback()
            raise e

        finally:
            cursor.close()
            conn.close()
