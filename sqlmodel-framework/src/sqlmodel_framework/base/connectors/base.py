"""Base connector classes for database connectivity.

Provides abstract base classes for all database connectors in the framework.
Designed for Bronze layer data ingestion patterns.
"""

from abc import ABC, abstractmethod
from contextlib import contextmanager
from typing import Any, Optional

from pydantic import BaseModel, ConfigDict


class ConnectorConfig(BaseModel):
    """Base configuration for database connectors.

    All connector configurations should inherit from this class
    and add their database-specific settings.
    """

    model_config = ConfigDict(extra="forbid")

    host: str
    port: int
    database: str
    connect_timeout: int = 30


class BaseConnector(ABC):
    """Abstract base class for all database connectors.

    Provides common interface for database connectivity across
    different database systems (PostgreSQL, SQL Server, MySQL, etc.)

    Subclasses must implement:
    - test_connection(): Verify connectivity
    - get_connection(): Get database connection object
    - get_tables(): List available tables
    """

    def __init__(self, config: ConnectorConfig):
        """Initialize connector with configuration.

        Args:
            config: ConnectorConfig instance with connection parameters
        """
        self.config = config

    @abstractmethod
    def test_connection(self) -> bool:
        """Test if connection can be established.

        Returns:
            True if connection successful, False otherwise
        """
        pass

    @abstractmethod
    def get_connection(self) -> Any:
        """Get database connection object.

        Returns:
            Database-specific connection object
        """
        pass

    @abstractmethod
    def get_tables(self, schema: Optional[str] = None) -> list[str]:
        """List available tables in the database.

        Args:
            schema: Optional schema name to filter tables

        Returns:
            List of table names
        """
        pass

    @contextmanager
    def connection_context(self):
        """Context manager for connection lifecycle.

        Ensures proper connection cleanup after use.

        Yields:
            Database connection object
        """
        conn = self.get_connection()
        try:
            yield conn
        finally:
            if hasattr(conn, 'close'):
                conn.close()