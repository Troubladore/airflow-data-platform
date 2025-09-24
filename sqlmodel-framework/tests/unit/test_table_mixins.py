"""Unit tests for table mixins and base classes.

Tests the fundamental building blocks of our data platform:
- ReferenceTableMixin behavior and soft deletes
- TransactionalTableMixin audit trails
- TemporalTableMixin effective time management
- Base table classes with proper ID patterns
"""

from datetime import UTC, datetime
from unittest.mock import patch

from sqlmodel import SQLModel

from sqlmodel_framework.base.models.table_mixins import (
    ReferenceTable,
    ReferenceTableMixin,
    TemporalTable,
    TemporalTableMixin,
    TransactionalTable,
    TransactionalTableMixin,
)


class TestReferenceTableMixin:
    """Test reference table mixin functionality"""

    def test_reference_mixin_defaults(self):
        """Test that reference mixin has correct default values"""

        class TestRefTable(ReferenceTableMixin, SQLModel):
            pass

        instance = TestRefTable()

        # Should start as active (inactivated_date is None)
        assert instance.inactivated_date is None

        # Should have systime set
        assert instance.systime is not None
        assert isinstance(instance.systime, datetime)

    def test_inactivate_functionality(self):
        """Test soft delete functionality via manual field setting"""

        class TestRefTable(ReferenceTableMixin, SQLModel):
            pass

        instance = TestRefTable()
        original_systime = instance.systime

        # Initially active (inactivated_date is None)
        assert instance.inactivated_date is None

        # Manually inactivate the record (as would be done in application code)
        mock_now = datetime(2024, 1, 15, 12, 0, 0, tzinfo=UTC)
        instance.inactivated_date = mock_now
        instance.systime = mock_now

        # Should now be inactive
        assert instance.inactivated_date is not None
        assert instance.inactivated_date == mock_now
        assert instance.systime == mock_now
        assert instance.systime != original_systime

    def test_reference_table_base_class(self):
        """Test ReferenceTable base class is abstract and inherits from mixin"""
        # Abstract base class - can't instantiate directly
        assert ReferenceTable.__abstract__ is True

        # Should inherit from ReferenceTableMixin
        assert issubclass(ReferenceTable, ReferenceTableMixin)

        # Mixin fields should be accessible through inheritance
        assert hasattr(ReferenceTable, "inactivated_date")
        assert hasattr(ReferenceTable, "systime")


class TestTransactionalTableMixin:
    """Test transactional table mixin functionality"""

    def test_transactional_mixin_defaults(self):
        """Test that transactional mixin has correct default values"""

        class TestTxnTable(TransactionalTableMixin, SQLModel):
            pass

        instance = TestTxnTable()

        # Should have all audit timestamps
        assert instance.systime is not None
        assert instance.created_at is not None
        assert instance.updated_at is not None

        # All should be datetime objects
        assert isinstance(instance.systime, datetime)
        assert isinstance(instance.created_at, datetime)
        assert isinstance(instance.updated_at, datetime)

    def test_timestamp_management(self):
        """Test manual timestamp management"""

        class TestTxnTable(TransactionalTableMixin, SQLModel):
            pass

        instance = TestTxnTable()
        original_systime = instance.systime
        original_updated_at = instance.updated_at
        original_created_at = instance.created_at

        # Manually update timestamps (as would be done in application code)
        mock_now = datetime(2024, 1, 15, 12, 0, 0, tzinfo=UTC)
        instance.systime = mock_now
        instance.updated_at = mock_now
        # created_at should remain unchanged

        # Should have updated modification timestamps
        assert instance.systime == mock_now
        assert instance.updated_at == mock_now

        # Should NOT have updated creation timestamp
        assert instance.created_at == original_created_at

        # Timestamps should have changed
        assert instance.systime != original_systime
        assert instance.updated_at != original_updated_at

    def test_transactional_table_base_class(self):
        """Test TransactionalTable base class is abstract and has mixin fields"""
        # Abstract base class - can't instantiate directly
        assert TransactionalTable.__abstract__ is True

        # Should inherit from TransactionalTableMixin
        assert issubclass(TransactionalTable, TransactionalTableMixin)

        # Mixin fields should be accessible through inheritance
        assert hasattr(TransactionalTable, "systime")
        assert hasattr(TransactionalTable, "created_at")
        assert hasattr(TransactionalTable, "updated_at")


class TestTemporalTableMixin:
    """Test temporal table mixin functionality"""

    def test_temporal_mixin_defaults(self):
        """Test that temporal mixin has correct default values"""

        class TestTemporalTable(TemporalTableMixin, SQLModel):
            pass

        instance = TestTemporalTable()

        # Should have temporal timestamps
        assert instance.effective_time is not None
        assert instance.systime is not None

        # Should be datetime objects
        assert isinstance(instance.effective_time, datetime)
        assert isinstance(instance.systime, datetime)

    def test_effective_time_management(self):
        """Test manual effective time management"""

        class TestTemporalTable(TemporalTableMixin, SQLModel):
            pass

        instance = TestTemporalTable()
        original_systime = instance.systime

        # Manually set custom effective time
        custom_effective_time = datetime(2024, 6, 15, 10, 30, 0, tzinfo=UTC)
        mock_systime = datetime(2024, 1, 15, 12, 0, 0, tzinfo=UTC)

        instance.effective_time = custom_effective_time
        instance.systime = mock_systime

        # Should have set custom effective time and updated systime
        assert instance.effective_time == custom_effective_time
        assert instance.systime == mock_systime
        assert instance.systime != original_systime

    def test_temporal_table_base_class(self):
        """Test TemporalTable base class is abstract and has mixin fields"""
        # Abstract base class - can't instantiate directly
        assert TemporalTable.__abstract__ is True

        # Should inherit from TemporalTableMixin
        assert issubclass(TemporalTable, TemporalTableMixin)

        # Mixin fields should be accessible through inheritance
        assert hasattr(TemporalTable, "effective_time")
        assert hasattr(TemporalTable, "systime")


class TestMixinInteractions:
    """Test interactions between different mixins"""

    def test_multiple_mixin_inheritance(self):
        """Test class inheriting multiple mixins"""

        class ComplexTable(ReferenceTableMixin, TransactionalTableMixin, SQLModel):
            pass

        instance = ComplexTable()

        # Should have fields from both mixins
        assert hasattr(instance, "inactivated_date")  # From reference
        assert hasattr(instance, "created_at")  # From transactional
        assert hasattr(instance, "updated_at")  # From transactional
        assert hasattr(instance, "systime")  # From both (should not conflict)

        # Should start active (inactivated_date is None)
        assert instance.inactivated_date is None

        # Manually inactivate the record
        mock_now = datetime(2024, 1, 15, 12, 0, 0, tzinfo=UTC)
        instance.inactivated_date = mock_now

        # Should now be inactivated
        assert instance.inactivated_date is not None

    def test_field_name_conflicts_handled(self):
        """Test that systime field doesn't conflict between mixins"""

        class ConflictTable(
            ReferenceTableMixin, TransactionalTableMixin, TemporalTableMixin, SQLModel
        ):
            pass

        instance = ConflictTable()

        # Should have systime (all mixins define it, but should resolve consistently)
        assert hasattr(instance, "systime")
        assert isinstance(instance.systime, datetime)

        # Should have fields from all mixins
        assert hasattr(instance, "inactivated_date")  # Reference
        assert hasattr(instance, "created_at")  # Transactional
        assert hasattr(instance, "updated_at")  # Transactional
        assert hasattr(instance, "effective_time")  # Temporal

        # Manual field management should work for all mixin fields
        mock_now = datetime.now(UTC)
        instance.systime = mock_now
        instance.inactivated_date = mock_now
        instance.effective_time = mock_now

        assert instance.systime == mock_now
        assert instance.inactivated_date == mock_now
        assert instance.effective_time == mock_now

        # All fields should be properly set
        assert instance.inactivated_date is not None  # Record is inactive when this is set


# Integration tests with actual database would go in tests/integration/
# These unit tests focus on the mixin logic and method behavior
