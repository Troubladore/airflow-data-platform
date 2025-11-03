"""Unit tests for Bronze layer ingestion pipeline.

Tests the BronzeIngestionPipeline base class for data ingestion patterns.
"""

import tempfile
from datetime import datetime
from pathlib import Path
from unittest.mock import Mock, patch
import pandas as pd
import pytest

# These imports will fail initially - that's expected in TDD
from sqlmodel_framework.base.loaders.bronze_ingestion import BronzeIngestionPipeline
from sqlmodel_framework.base.connectors.base import BaseConnector, ConnectorConfig


class TestBronzeIngestionPipeline:
    """Test BronzeIngestionPipeline base class"""

    def test_bronze_pipeline_is_abstract(self):
        """Test that BronzeIngestionPipeline cannot be instantiated directly"""
        mock_connector = Mock(spec=BaseConnector)

        with tempfile.TemporaryDirectory() as tmpdir:
            bronze_path = Path(tmpdir) / "bronze"

            # Should not be able to instantiate abstract class
            with pytest.raises(TypeError):
                BronzeIngestionPipeline(mock_connector, bronze_path)

    def test_bronze_pipeline_initialization(self):
        """Test pipeline initialization with connector and path"""

        class TestPipeline(BronzeIngestionPipeline):
            """Test implementation of pipeline"""

            def extract_table(self, table_name: str, **kwargs) -> pd.DataFrame:
                return pd.DataFrame({"id": [1, 2], "name": ["A", "B"]})

        mock_connector = Mock(spec=BaseConnector)

        with tempfile.TemporaryDirectory() as tmpdir:
            bronze_path = Path(tmpdir) / "bronze"

            pipeline = TestPipeline(mock_connector, bronze_path)

            assert pipeline.connector == mock_connector
            assert pipeline.bronze_path == bronze_path
            assert bronze_path.exists()  # Directory should be created

    def test_add_bronze_metadata(self):
        """Test adding Bronze metadata to DataFrame"""

        class TestPipeline(BronzeIngestionPipeline):
            def extract_table(self, table_name: str, **kwargs) -> pd.DataFrame:
                return pd.DataFrame()

        mock_connector = Mock(spec=BaseConnector)

        with tempfile.TemporaryDirectory() as tmpdir:
            pipeline = TestPipeline(mock_connector, Path(tmpdir))

            # Create test DataFrame
            df = pd.DataFrame({
                "id": [1, 2, 3],
                "name": ["Alice", "Bob", "Charlie"]
            })

            # Add Bronze metadata
            result_df = pipeline.add_bronze_metadata(
                df,
                source_system="test_system",
                source_table="users",
                source_host="localhost",
                extraction_method="incremental"
            )

            # Check metadata columns were added
            assert "bronze_load_timestamp" in result_df.columns
            assert "bronze_source_system" in result_df.columns
            assert "bronze_source_table" in result_df.columns
            assert "bronze_source_host" in result_df.columns
            assert "bronze_extraction_method" in result_df.columns

            # Check values
            assert result_df["bronze_source_system"].iloc[0] == "test_system"
            assert result_df["bronze_source_table"].iloc[0] == "users"
            assert result_df["bronze_source_host"].iloc[0] == "localhost"
            assert result_df["bronze_extraction_method"].iloc[0] == "incremental"

            # Check timestamp is ISO format string
            timestamp_str = result_df["bronze_load_timestamp"].iloc[0]
            assert isinstance(timestamp_str, str)
            # Should parse as valid ISO datetime
            datetime.fromisoformat(timestamp_str)

    def test_write_bronze_parquet(self):
        """Test writing Bronze data to Parquet format"""

        class TestPipeline(BronzeIngestionPipeline):
            def extract_table(self, table_name: str, **kwargs) -> pd.DataFrame:
                return pd.DataFrame()

        mock_connector = Mock(spec=BaseConnector)

        with tempfile.TemporaryDirectory() as tmpdir:
            bronze_path = Path(tmpdir) / "bronze"
            pipeline = TestPipeline(mock_connector, bronze_path)

            # Create test DataFrame with Bronze metadata
            df = pd.DataFrame({
                "id": [1, 2],
                "name": ["Alice", "Bob"],
                "bronze_load_timestamp": ["2025-01-15T10:30:00", "2025-01-15T10:30:00"],
                "bronze_source_system": ["test", "test"],
                "bronze_source_table": ["users", "users"],
                "bronze_source_host": ["localhost", "localhost"],
                "bronze_extraction_method": ["full_snapshot", "full_snapshot"]
            })

            # Write Bronze data
            paths = pipeline.write_bronze(
                df,
                source_system="test_system",
                table_name="users",
                formats=["parquet"]
            )

            # Check output
            assert "parquet" in paths
            parquet_path = Path(paths["parquet"])
            assert parquet_path.exists()
            assert parquet_path.suffix == ".parquet"
            assert "test_system/users" in str(parquet_path)

            # Read back and verify
            df_read = pd.read_parquet(parquet_path)
            assert len(df_read) == 2
            assert df_read["name"].tolist() == ["Alice", "Bob"]

    def test_write_bronze_json(self):
        """Test writing Bronze data to JSON format"""

        class TestPipeline(BronzeIngestionPipeline):
            def extract_table(self, table_name: str, **kwargs) -> pd.DataFrame:
                return pd.DataFrame()

        mock_connector = Mock(spec=BaseConnector)

        with tempfile.TemporaryDirectory() as tmpdir:
            bronze_path = Path(tmpdir) / "bronze"
            pipeline = TestPipeline(mock_connector, bronze_path)

            # Create test DataFrame
            df = pd.DataFrame({
                "id": [1, 2],
                "name": ["Alice", "Bob"],
                "bronze_load_timestamp": ["2025-01-15T10:30:00", "2025-01-15T10:30:00"],
                "bronze_source_system": ["test", "test"],
                "bronze_source_table": ["users", "users"],
                "bronze_source_host": ["localhost", "localhost"],
                "bronze_extraction_method": ["full_snapshot", "full_snapshot"]
            })

            # Write Bronze data as JSON
            paths = pipeline.write_bronze(
                df,
                source_system="test_system",
                table_name="users",
                formats=["json"]
            )

            # Check output
            assert "json" in paths
            json_path = Path(paths["json"])
            assert json_path.exists()
            assert json_path.suffix == ".json"

            # Read back and verify
            df_read = pd.read_json(json_path, orient="records")
            assert len(df_read) == 2
            assert df_read["name"].tolist() == ["Alice", "Bob"]

    def test_write_bronze_multiple_formats(self):
        """Test writing Bronze data to multiple formats"""

        class TestPipeline(BronzeIngestionPipeline):
            def extract_table(self, table_name: str, **kwargs) -> pd.DataFrame:
                return pd.DataFrame()

        mock_connector = Mock(spec=BaseConnector)

        with tempfile.TemporaryDirectory() as tmpdir:
            bronze_path = Path(tmpdir) / "bronze"
            pipeline = TestPipeline(mock_connector, bronze_path)

            df = pd.DataFrame({
                "id": [1],
                "value": [100]
            })

            # Write in both formats
            paths = pipeline.write_bronze(
                df,
                source_system="test",
                table_name="data",
                formats=["parquet", "json"]
            )

            assert "parquet" in paths
            assert "json" in paths
            assert Path(paths["parquet"]).exists()
            assert Path(paths["json"]).exists()

    def test_write_bronze_timestamp_in_filename(self):
        """Test that Bronze files have timestamp in filename"""

        class TestPipeline(BronzeIngestionPipeline):
            def extract_table(self, table_name: str, **kwargs) -> pd.DataFrame:
                return pd.DataFrame()

        mock_connector = Mock(spec=BaseConnector)

        with tempfile.TemporaryDirectory() as tmpdir:
            bronze_path = Path(tmpdir) / "bronze"
            pipeline = TestPipeline(mock_connector, bronze_path)

            df = pd.DataFrame({"id": [1]})

            paths = pipeline.write_bronze(
                df,
                source_system="test",
                table_name="data",
                formats=["parquet"]
            )

            parquet_file = Path(paths["parquet"]).name
            # Check timestamp format YYYYMMDD_HHMMSS in filename
            import re
            assert re.match(r"\d{8}_\d{6}\.parquet", parquet_file)

    def test_extract_table_must_be_implemented(self):
        """Test that extract_table must be implemented by subclasses"""

        class IncompleteTestPipeline(BronzeIngestionPipeline):
            """Pipeline missing extract_table implementation"""
            pass

        mock_connector = Mock(spec=BaseConnector)

        with tempfile.TemporaryDirectory() as tmpdir:
            # Should fail to instantiate without implementing abstract method
            with pytest.raises(TypeError):
                IncompleteTestPipeline(mock_connector, Path(tmpdir))