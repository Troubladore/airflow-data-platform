"""Unit tests for database connectors.

Tests the fundamental building blocks of database connectivity:
- BaseConnector abstract class and ConnectorConfig
- PostgresConnector with Kerberos support
- Connection context managers
"""

import subprocess
from contextlib import contextmanager
from unittest.mock import MagicMock, Mock, patch
import pytest
from typing import Any, Optional

# These imports will fail initially - that's expected in TDD
from sqlmodel_framework.base.connectors.base import BaseConnector, ConnectorConfig
from sqlmodel_framework.base.connectors.postgres import PostgresConnector, PostgresConfig


class TestConnectorConfig:
    """Test ConnectorConfig base configuration"""

    def test_connector_config_required_fields(self):
        """Test that ConnectorConfig requires all mandatory fields"""
        # Should create with all required fields
        config = ConnectorConfig(
            host="localhost",
            port=5432,
            database="testdb"
        )

        assert config.host == "localhost"
        assert config.port == 5432
        assert config.database == "testdb"
        assert config.connect_timeout == 30  # default value

    def test_connector_config_with_custom_timeout(self):
        """Test ConnectorConfig with custom timeout"""
        config = ConnectorConfig(
            host="localhost",
            port=5432,
            database="testdb",
            connect_timeout=60
        )

        assert config.connect_timeout == 60

    def test_connector_config_forbids_extra_fields(self):
        """Test that ConnectorConfig doesn't allow unknown fields"""
        with pytest.raises(Exception):  # Pydantic will raise validation error
            ConnectorConfig(
                host="localhost",
                port=5432,
                database="testdb",
                unknown_field="should_fail"
            )


class TestBaseConnector:
    """Test BaseConnector abstract base class"""

    def test_base_connector_is_abstract(self):
        """Test that BaseConnector cannot be instantiated directly"""
        config = ConnectorConfig(
            host="localhost",
            port=5432,
            database="testdb"
        )

        # Should not be able to instantiate abstract class
        with pytest.raises(TypeError):
            BaseConnector(config)

    def test_base_connector_requires_abstract_methods(self):
        """Test that subclasses must implement abstract methods"""

        class IncompleteConnector(BaseConnector):
            """Incomplete implementation missing abstract methods"""
            pass

        config = ConnectorConfig(
            host="localhost",
            port=5432,
            database="testdb"
        )

        # Should fail to instantiate without implementing abstract methods
        with pytest.raises(TypeError):
            IncompleteConnector(config)

    def test_base_connector_with_complete_implementation(self):
        """Test that properly implemented subclass can be instantiated"""

        class CompleteConnector(BaseConnector):
            """Complete implementation of all abstract methods"""

            def test_connection(self) -> bool:
                return True

            def get_connection(self) -> Any:
                return Mock()

            def get_tables(self, schema: Optional[str] = None) -> list[str]:
                return ["table1", "table2"]

        config = ConnectorConfig(
            host="localhost",
            port=5432,
            database="testdb"
        )

        # Should successfully instantiate
        connector = CompleteConnector(config)
        assert connector.config == config
        assert connector.test_connection() is True
        assert connector.get_tables() == ["table1", "table2"]

    def test_connection_context_manager(self):
        """Test the connection_context context manager"""

        class TestConnector(BaseConnector):
            def test_connection(self) -> bool:
                return True

            def get_connection(self) -> Any:
                mock_conn = Mock()
                mock_conn.close = Mock()
                return mock_conn

            def get_tables(self, schema: Optional[str] = None) -> list[str]:
                return []

        config = ConnectorConfig(
            host="localhost",
            port=5432,
            database="testdb"
        )

        connector = TestConnector(config)

        # Test context manager calls close
        with connector.connection_context() as conn:
            assert conn is not None
            assert hasattr(conn, 'close')

        # Verify close was called
        conn.close.assert_called_once()


class TestPostgresConfig:
    """Test PostgresConfig configuration"""

    def test_postgres_config_defaults(self):
        """Test PostgresConfig with default values"""
        config = PostgresConfig(
            host="localhost",
            database="testdb"
        )

        assert config.host == "localhost"
        assert config.port == 5432  # Postgres default
        assert config.database == "testdb"
        assert config.use_kerberos is False
        assert config.gssencmode == "prefer"
        assert config.krb5_ccname is None

    def test_postgres_config_with_kerberos(self):
        """Test PostgresConfig with Kerberos settings"""
        config = PostgresConfig(
            host="pgserver.example.com",
            database="testdb",
            use_kerberos=True,
            gssencmode="require",
            krb5_ccname="/tmp/krb5cc_1000"
        )

        assert config.use_kerberos is True
        assert config.gssencmode == "require"
        assert config.krb5_ccname == "/tmp/krb5cc_1000"


class TestPostgresConnector:
    """Test PostgresConnector implementation"""

    @patch('subprocess.run')
    def test_get_kerberos_username_success(self, mock_run):
        """Test successful Kerberos username extraction"""
        # Mock klist output
        mock_run.return_value = Mock(
            returncode=0,
            stdout="Ticket cache: FILE:/tmp/krb5cc_1000\nDefault principal: testuser@EXAMPLE.COM\n"
        )

        config = PostgresConfig(
            host="localhost",
            database="testdb",
            use_kerberos=True
        )

        connector = PostgresConnector(config)
        username = connector._get_kerberos_username()

        assert username == "testuser"
        mock_run.assert_called_once_with(['klist'], capture_output=True, text=True)

    @patch('subprocess.run')
    def test_get_kerberos_username_no_ticket(self, mock_run):
        """Test Kerberos username extraction with no ticket"""
        mock_run.return_value = Mock(returncode=1, stdout="")

        config = PostgresConfig(
            host="localhost",
            database="testdb",
            use_kerberos=True
        )

        connector = PostgresConnector(config)
        username = connector._get_kerberos_username()

        assert username is None

    @patch('subprocess.run')
    def test_get_kerberos_username_exception(self, mock_run):
        """Test Kerberos username extraction handles exceptions"""
        mock_run.side_effect = Exception("Command not found")

        config = PostgresConfig(
            host="localhost",
            database="testdb",
            use_kerberos=True
        )

        connector = PostgresConnector(config)
        username = connector._get_kerberos_username()

        assert username is None

    @patch('psycopg2.connect')
    def test_get_connection_without_kerberos(self, mock_connect):
        """Test PostgreSQL connection without Kerberos"""
        mock_connection = Mock()
        mock_connect.return_value = mock_connection

        config = PostgresConfig(
            host="localhost",
            port=5433,
            database="testdb",
            use_kerberos=False
        )

        connector = PostgresConnector(config)
        conn = connector.get_connection()

        assert conn == mock_connection
        mock_connect.assert_called_once_with(
            host="localhost",
            port=5433,
            database="testdb"
        )

    @patch('psycopg2.connect')
    @patch('subprocess.run')
    def test_get_connection_with_kerberos(self, mock_run, mock_connect):
        """Test PostgreSQL connection with Kerberos authentication"""
        # Mock klist to return a username
        mock_run.return_value = Mock(
            returncode=0,
            stdout="Default principal: pguser@EXAMPLE.COM\n"
        )

        mock_connection = Mock()
        mock_connect.return_value = mock_connection

        config = PostgresConfig(
            host="pgserver.example.com",
            database="testdb",
            use_kerberos=True,
            gssencmode="require"
        )

        connector = PostgresConnector(config)
        conn = connector.get_connection()

        assert conn == mock_connection
        mock_connect.assert_called_once_with(
            host="pgserver.example.com",
            port=5432,
            database="testdb",
            user="pguser",
            gssencmode="require"
        )

    @patch('psycopg2.connect')
    def test_test_connection_success(self, mock_connect):
        """Test successful connection test"""
        mock_connection = Mock()
        mock_connection.close = Mock()
        mock_connect.return_value = mock_connection

        config = PostgresConfig(
            host="localhost",
            database="testdb"
        )

        connector = PostgresConnector(config)
        result = connector.test_connection()

        assert result is True
        mock_connection.close.assert_called_once()

    @patch('psycopg2.connect')
    def test_test_connection_failure(self, mock_connect):
        """Test failed connection test"""
        mock_connect.side_effect = Exception("Connection failed")

        config = PostgresConfig(
            host="localhost",
            database="testdb"
        )

        connector = PostgresConnector(config)
        result = connector.test_connection()

        assert result is False

    @patch('psycopg2.connect')
    def test_get_tables(self, mock_connect):
        """Test listing tables in a schema"""
        # Mock connection and cursor
        mock_cursor = Mock()
        mock_cursor.fetchall.return_value = [("table1",), ("table2",), ("table3",)]
        mock_cursor.__enter__ = Mock(return_value=mock_cursor)
        mock_cursor.__exit__ = Mock(return_value=None)

        mock_connection = Mock()
        mock_connection.cursor.return_value = mock_cursor
        mock_connection.__enter__ = Mock(return_value=mock_connection)
        mock_connection.__exit__ = Mock(return_value=None)
        mock_connection.close = Mock()

        mock_connect.return_value = mock_connection

        config = PostgresConfig(
            host="localhost",
            database="testdb"
        )

        connector = PostgresConnector(config)
        tables = connector.get_tables(schema="public")

        assert tables == ["table1", "table2", "table3"]
        mock_cursor.execute.assert_called_once()

        # Verify the SQL query
        call_args = mock_cursor.execute.call_args
        sql = call_args[0][0]
        params = call_args[0][1]

        assert "information_schema.tables" in sql
        assert params == ("public",)