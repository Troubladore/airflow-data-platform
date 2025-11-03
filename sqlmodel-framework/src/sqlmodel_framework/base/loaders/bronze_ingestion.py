"""Bronze layer ingestion pipeline base class.

Provides base functionality for Bronze layer data ingestion:
- Extract data from source systems
- Add Bronze metadata
- Write to Bronze storage in multiple formats
"""

from abc import ABC, abstractmethod
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional

import pandas as pd


class BronzeIngestionPipeline(ABC):
    """Base class for Bronze layer ingestion pipelines.

    Provides common functionality for extracting data from source systems,
    adding Bronze metadata, and writing to Bronze storage.

    Subclasses must implement:
    - extract_table(): Extract data from source table

    Example:
        class PagilaBronzeLoader(BronzeIngestionPipeline):
            def extract_table(self, table_name: str) -> pd.DataFrame:
                with self.connector.connection_context() as conn:
                    return pd.read_sql(f"SELECT * FROM {table_name}", conn)
    """

    def __init__(self, connector: Any, bronze_path: Path):
        """Initialize Bronze ingestion pipeline.

        Args:
            connector: Database connector instance
            bronze_path: Path to Bronze layer storage directory
        """
        self.connector = connector
        self.bronze_path = Path(bronze_path)
        self.bronze_path.mkdir(parents=True, exist_ok=True)

    @abstractmethod
    def extract_table(self, table_name: str, **kwargs) -> pd.DataFrame:
        """Extract data from source table.

        Args:
            table_name: Name of table to extract
            **kwargs: Additional extraction parameters

        Returns:
            DataFrame with extracted data
        """
        pass

    def add_bronze_metadata(
        self,
        df: pd.DataFrame,
        source_system: str,
        source_table: str,
        source_host: str,
        extraction_method: str = "full_snapshot"
    ) -> pd.DataFrame:
        """Add standard Bronze metadata to DataFrame.

        Args:
            df: DataFrame to add metadata to
            source_system: Source system identifier (e.g., 'pagila_kerberos')
            source_table: Original source table name
            source_host: Database host where data was extracted from
            extraction_method: Method used for extraction (full_snapshot, incremental, cdc)

        Returns:
            DataFrame with Bronze metadata columns added
        """
        df = df.copy()  # Don't modify original
        df['bronze_load_timestamp'] = datetime.now().isoformat()
        df['bronze_source_system'] = source_system
        df['bronze_source_table'] = source_table
        df['bronze_source_host'] = source_host
        df['bronze_extraction_method'] = extraction_method
        return df

    def write_bronze(
        self,
        df: pd.DataFrame,
        source_system: str,
        table_name: str,
        formats: list[str] = ['parquet', 'json']
    ) -> Dict[str, str]:
        """Write DataFrame to Bronze storage.

        Args:
            df: DataFrame to write
            source_system: Source system identifier for directory structure
            table_name: Table name for directory structure
            formats: Output formats ('parquet', 'json')

        Returns:
            Dictionary mapping format to output file path
        """
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_dir = self.bronze_path / source_system / table_name
        output_dir.mkdir(parents=True, exist_ok=True)

        paths = {}

        if 'parquet' in formats:
            parquet_path = output_dir / f"{timestamp}.parquet"
            df.to_parquet(parquet_path)
            paths['parquet'] = str(parquet_path)

        if 'json' in formats:
            json_path = output_dir / f"{timestamp}.json"
            df.to_json(json_path, orient='records', date_format='iso')
            paths['json'] = str(json_path)

        return paths