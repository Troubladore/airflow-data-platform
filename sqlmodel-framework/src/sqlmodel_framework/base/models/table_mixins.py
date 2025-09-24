"""Data Platform Framework - Table Type Mixins

Table type mixins and base classes for consistent schema patterns across all datakits.
Extracted and adapted from medallion-demo patterns for broader platform use.

Table Types:
- Reference tables (lookup data with soft deletes)
- Transactional tables (business entities with audit trails)
- Temporal tables (history tracking with system versioning)
"""

import uuid
from datetime import UTC, datetime
from typing import Optional

from sqlalchemy import SMALLINT, TIMESTAMP, Column, text
from sqlmodel import Field, SQLModel


class ReferenceTableMixin:
    """Mixin for reference/lookup tables.

    Adds standard fields for reference data:
    - inactivated_date: UTC datetime when record was inactivated (NULL = active)
    - systime: audit timestamp for when record was created/last modified

    Reference tables should use SMALLINT primary keys for performance.

    Active vs Inactive Logic:
    - inactivated_date IS NULL → Record is ACTIVE
    - inactivated_date IS NOT NULL → Record was INACTIVATED on that date
    """

    inactivated_date: datetime | None = Field(
        default=None,
        sa_column=Column(TIMESTAMP(timezone=True), nullable=True),
        description="UTC datetime when record was inactivated (NULL = active)",
    )

    systime: datetime = Field(
        default_factory=lambda: datetime.now(UTC),
        sa_column=Column(
            TIMESTAMP(timezone=True), nullable=False, server_default=text("CURRENT_TIMESTAMP")
        ),
        description="Audit timestamp for creation/modification",
    )

    # Note: For active/inactive logic, check inactivated_date IS NULL (active) or IS NOT NULL (inactive)


class TransactionalTableMixin:
    """Mixin for transactional/business entity tables.

    Adds standard audit fields for transactional data:
    - systime: audit timestamp for when record was created/last modified
    - created_at: explicit creation timestamp (immutable)
    - updated_at: last update timestamp (updated on modify)

    Transactional tables typically use UUID primary keys for global uniqueness.
    """

    systime: datetime = Field(
        default_factory=lambda: datetime.now(UTC),
        sa_column=Column(
            TIMESTAMP(timezone=True), nullable=False, server_default=text("CURRENT_TIMESTAMP")
        ),
        description="System audit timestamp",
    )

    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC),
        sa_column=Column(TIMESTAMP(timezone=True), nullable=False),
        description="Record creation timestamp (immutable)",
    )

    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC),
        sa_column=Column(TIMESTAMP(timezone=True), nullable=False),
        description="Last update timestamp",
    )

    # Note: For timestamp management, updated_at should be handled by application logic or triggers


class TemporalTableMixin:
    """Mixin for temporal tables (current + history tracking).

    Adds standard fields for temporal data management:
    - effective_time: Business effective time for this record
    - systime: System time when record was processed

    Temporal tables work in pairs:
    - Primary table: Current state (e.g., 'trades')
    - History table: Historical states (e.g., 'trades__history')

    History tables automatically created via triggers when primary table changes.

    Note: Field exclusions supported via annotations:
    - Field(temporal_exclude=True) - Exclude specific fields from history
    - __temporal_exclude__ = ['field1', 'field2'] - Class-level exclusions
    """

    effective_time: datetime = Field(
        default_factory=lambda: datetime.now(UTC),
        sa_column=Column(TIMESTAMP(timezone=True), nullable=False),
        description="Business effective time for this record",
    )

    systime: datetime = Field(
        default_factory=lambda: datetime.now(UTC),
        sa_column=Column(
            TIMESTAMP(timezone=True), nullable=False, server_default=text("CURRENT_TIMESTAMP")
        ),
        description="System processing timestamp",
        schema_extra={"temporal_exclude": True},  # Exclude from history tracking
    )

    # Note: For temporal management, effective_time should be set explicitly and systime handled by triggers


# Base classes combining mixins with common ID patterns


class ReferenceTable(ReferenceTableMixin, SQLModel, table=True):
    """Base class for reference/lookup tables.

    Uses SMALLINT primary key for performance with lookup data.
    Includes soft delete functionality via inactivated_date.
    Subclasses must define their own primary key field.
    """

    # Abstract base - subclasses define their primary key
    __abstract__ = True


class TransactionalTable(TransactionalTableMixin, SQLModel, table=True):
    """Base class for transactional/business entity tables.

    Uses UUID primary key for global uniqueness.
    Includes comprehensive audit trail fields.
    Subclasses must define their own primary key field.
    """

    # Abstract base - subclasses define their primary key
    __abstract__ = True


class TemporalTable(TemporalTableMixin, SQLModel, table=True):
    """Base class for temporal tables with history tracking.

    Uses UUID primary key and includes temporal management fields.
    Designed to work with history table triggers and validation.
    Subclasses must define their own primary key field.
    """

    # Abstract base - subclasses define their primary key
    __abstract__ = True
