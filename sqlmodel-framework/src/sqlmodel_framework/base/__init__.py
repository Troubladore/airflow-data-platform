# Data Platform Framework - Base Patterns
#
# Foundational patterns for data object lifecycle management:
# - Table type mixins (Reference, Transactional, Temporal, Bronze)
# - Database connectors with Kerberos support
# - Bronze layer ingestion pipelines
# - Data loaders and merge management
# - Temporal table builders with trigger validation
# - Test data factories for component validation
#

from .connectors import BaseConnector, ConnectorConfig, PostgresConnector, PostgresConfig
from .loaders import BronzeIngestionPipeline, DataFactory
from .models import (
    BronzeMetadata,
    ReferenceTable,
    ReferenceTableMixin,
    TemporalTable,
    TemporalTableMixin,
    TransactionalTable,
    TransactionalTableMixin,
)

__all__ = [
    # Connectors
    "BaseConnector",
    "ConnectorConfig",
    "PostgresConnector",
    "PostgresConfig",
    # Loaders
    "BronzeIngestionPipeline",
    "DataFactory",
    # Models
    "BronzeMetadata",
    "ReferenceTable",
    "ReferenceTableMixin",
    "TemporalTable",
    "TemporalTableMixin",
    "TransactionalTable",
    "TransactionalTableMixin",
]