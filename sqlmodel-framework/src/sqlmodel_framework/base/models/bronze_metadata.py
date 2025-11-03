"""Bronze layer metadata mixin for data ingestion tracking.

Provides standard fields for Bronze layer tables to track:
- When data was loaded
- Where data came from
- How data was extracted
"""

from datetime import datetime, UTC
from sqlmodel import Field


class BronzeMetadata:
    """Standard Bronze layer metadata fields.

    Add to any Bronze table definition to track ingestion metadata:

    Example:
        class FilmBronze(BronzeMetadata, SQLModel, table=True):
            film_id: int = Field(primary_key=True)
            title: str
            # ... other fields

    This will add:
    - bronze_load_timestamp: When record was loaded
    - bronze_source_system: Source system identifier
    - bronze_source_table: Original source table
    - bronze_source_host: Database host
    - bronze_extraction_method: How data was extracted
    """

    bronze_load_timestamp: datetime = Field(
        default_factory=lambda: datetime.now(UTC),
        description="When this record was loaded into Bronze layer",
        index=True
    )

    bronze_source_system: str = Field(
        ...,
        description="Source system identifier (e.g., 'pagila_kerberos')"
    )

    bronze_source_table: str = Field(
        ...,
        description="Original source table name"
    )

    bronze_source_host: str = Field(
        ...,
        description="Database host where data was extracted from"
    )

    bronze_extraction_method: str = Field(
        default="full_snapshot",
        description="Extraction method: full_snapshot, incremental, cdc"
    )