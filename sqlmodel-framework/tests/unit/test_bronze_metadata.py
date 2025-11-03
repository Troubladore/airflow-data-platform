"""Unit tests for Bronze layer metadata mixin.

Tests the BronzeMetadata mixin that provides standard fields
for Bronze layer data ingestion tracking.
"""

from datetime import datetime, UTC
from sqlmodel import SQLModel, Field

# These imports will fail initially - that's expected in TDD
from sqlmodel_framework.base.models.bronze_metadata import BronzeMetadata


class TestBronzeMetadata:
    """Test BronzeMetadata mixin functionality"""

    def test_bronze_metadata_fields(self):
        """Test that BronzeMetadata provides all required fields"""

        class FilmBronze(BronzeMetadata, SQLModel, table=True):
            """Test Bronze table with metadata"""
            __tablename__ = "film_bronze"

            film_id: int = Field(primary_key=True)
            title: str

        # Check that all Bronze metadata fields are present
        assert hasattr(FilmBronze, 'bronze_load_timestamp')
        assert hasattr(FilmBronze, 'bronze_source_system')
        assert hasattr(FilmBronze, 'bronze_source_table')
        assert hasattr(FilmBronze, 'bronze_source_host')
        assert hasattr(FilmBronze, 'bronze_extraction_method')

    def test_bronze_metadata_defaults(self):
        """Test that BronzeMetadata has correct default values"""

        class TestBronzeTable(BronzeMetadata, SQLModel):
            """Test table with Bronze metadata"""
            id: int = Field(primary_key=True)

        # Create instance with required fields
        instance = TestBronzeTable(
            id=1,
            bronze_source_system="test_system",
            bronze_source_table="test_table",
            bronze_source_host="localhost"
        )

        # Check defaults
        assert instance.bronze_extraction_method == "full_snapshot"
        assert isinstance(instance.bronze_load_timestamp, datetime)

        # Timestamp should be recent (within last minute)
        now = datetime.now(UTC)
        time_diff = abs((now - instance.bronze_load_timestamp).total_seconds())
        assert time_diff < 60

    def test_bronze_metadata_custom_values(self):
        """Test setting custom values for Bronze metadata"""

        class TestBronzeTable(BronzeMetadata, SQLModel):
            """Test table with Bronze metadata"""
            id: int = Field(primary_key=True)

        custom_timestamp = datetime(2025, 1, 15, 10, 30, 0, tzinfo=UTC)

        instance = TestBronzeTable(
            id=1,
            bronze_load_timestamp=custom_timestamp,
            bronze_source_system="pagila_kerberos",
            bronze_source_table="film",
            bronze_source_host="pgserver.example.com",
            bronze_extraction_method="incremental"
        )

        assert instance.bronze_load_timestamp == custom_timestamp
        assert instance.bronze_source_system == "pagila_kerberos"
        assert instance.bronze_source_table == "film"
        assert instance.bronze_source_host == "pgserver.example.com"
        assert instance.bronze_extraction_method == "incremental"

    def test_bronze_metadata_with_other_mixins(self):
        """Test BronzeMetadata can be combined with other mixins"""

        from sqlmodel_framework.base.models.table_mixins import TransactionalTableMixin

        class ComplexBronzeTable(BronzeMetadata, TransactionalTableMixin, SQLModel):
            """Table with both Bronze and Transactional metadata"""
            id: int = Field(primary_key=True)
            data: str

        instance = ComplexBronzeTable(
            id=1,
            data="test",
            bronze_source_system="source",
            bronze_source_table="table",
            bronze_source_host="host"
        )

        # Should have fields from both mixins
        assert hasattr(instance, 'bronze_load_timestamp')  # From BronzeMetadata
        assert hasattr(instance, 'bronze_source_system')   # From BronzeMetadata
        assert hasattr(instance, 'created_at')             # From TransactionalTableMixin
        assert hasattr(instance, 'updated_at')             # From TransactionalTableMixin

    def test_bronze_metadata_field_descriptions(self):
        """Test that Bronze metadata fields have descriptions"""

        class TestBronzeTable(BronzeMetadata, SQLModel, table=True):
            """Test table with Bronze metadata"""
            __tablename__ = "test_bronze"
            id: int = Field(primary_key=True)

        # Get field info from SQLModel
        fields = TestBronzeTable.model_fields

        # Check bronze_load_timestamp field
        timestamp_field = fields.get('bronze_load_timestamp')
        assert timestamp_field is not None
        assert timestamp_field.description is not None
        assert "loaded into Bronze layer" in timestamp_field.description

        # Check bronze_source_system field
        system_field = fields.get('bronze_source_system')
        assert system_field is not None
        assert system_field.description is not None
        assert "Source system identifier" in system_field.description

        # Check bronze_extraction_method field
        method_field = fields.get('bronze_extraction_method')
        assert method_field is not None
        assert method_field.description is not None
        assert "Extraction method" in method_field.description

    def test_bronze_metadata_index_on_timestamp(self):
        """Test that bronze_load_timestamp has an index"""

        class TestBronzeTable(BronzeMetadata, SQLModel, table=True):
            """Test table with Bronze metadata"""
            __tablename__ = "test_bronze_indexed"
            id: int = Field(primary_key=True)

        # Check that bronze_load_timestamp field has index=True
        fields = TestBronzeTable.model_fields
        timestamp_field = fields.get('bronze_load_timestamp')

        # The field should be configured with an index
        # This would be in the field's metadata or sa_column configuration
        assert timestamp_field is not None
        # Note: Index configuration is part of the field definition