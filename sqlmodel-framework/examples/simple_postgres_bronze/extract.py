#!/usr/bin/env python3
"""
Simple Bronze layer extraction example using SQLModel Framework.

This script demonstrates:
1. Using framework connectors instead of raw database libraries
2. Extending BronzeIngestionPipeline for data extraction
3. Adding Bronze metadata automatically
4. Writing to Bronze storage in multiple formats
"""

import os
import sys
from pathlib import Path
from datetime import datetime
from typing import Optional
import pandas as pd
from dotenv import load_dotenv

# Import framework components
from sqlmodel_framework.base.connectors import PostgresConnector, PostgresConfig
from sqlmodel_framework.base.loaders import BronzeIngestionPipeline

# Load environment variables
load_dotenv()


class SimpleBronzePipeline(BronzeIngestionPipeline):
    """
    Simple Bronze ingestion pipeline for PostgreSQL.

    Extends the framework's base pipeline to implement
    custom extraction logic.
    """

    def extract_table(
        self,
        table_name: str,
        limit: Optional[int] = None,
        where_clause: Optional[str] = None
    ) -> pd.DataFrame:
        """
        Extract data from a source table.

        Args:
            table_name: Name of the table to extract
            limit: Optional row limit for testing
            where_clause: Optional WHERE clause for filtering

        Returns:
            DataFrame with extracted data
        """
        # Build query
        query = f"SELECT * FROM {table_name}"

        if where_clause:
            query += f" WHERE {where_clause}"

        if limit:
            query += f" LIMIT {limit}"

        print(f"Extracting from {table_name}...")
        print(f"  Query: {query}")

        # Execute query using framework's connection management
        with self.connector.connection_context() as conn:
            df = pd.read_sql(query, conn)

        print(f"  Extracted {len(df)} rows")

        # Add Bronze metadata using framework helper
        df = self.add_bronze_metadata(
            df,
            source_system="pagila_example",
            source_table=table_name,
            source_host=self.connector.config.host,
            extraction_method="full_snapshot"
        )

        return df


def main():
    """
    Main extraction workflow.
    """
    print("=" * 60)
    print("Simple PostgreSQL Bronze Extraction Example")
    print("=" * 60)

    # 1. Configure database connection
    # The framework handles all connection details
    config = PostgresConfig(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", 5432)),
        database=os.getenv("DB_NAME", "pagila"),
        username=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD", "postgres")
    )

    print(f"\nConnecting to {config.host}:{config.port}/{config.database}")

    # 2. Create connector
    # Framework provides connection pooling, retry logic, etc.
    connector = PostgresConnector(config)

    # 3. Test connection
    if not connector.test_connection():
        print("ERROR: Could not connect to database")
        sys.exit(1)

    print("✓ Connected successfully")

    # 4. List available tables
    tables = connector.get_tables(schema="public")
    print(f"\nFound {len(tables)} tables in database")

    # 5. Create Bronze pipeline
    bronze_path = Path("/tmp/bronze/simple_example")
    bronze_path.mkdir(parents=True, exist_ok=True)

    pipeline = SimpleBronzePipeline(
        connector=connector,
        bronze_path=bronze_path
    )

    # 6. Define tables to extract
    # In production, this might come from configuration
    tables_to_extract = [
        {"name": "film", "limit": 100},
        {"name": "actor", "limit": 50},
        {"name": "customer", "limit": 25},
    ]

    print(f"\nExtracting {len(tables_to_extract)} tables to Bronze")
    print(f"Bronze path: {bronze_path}")
    print("-" * 60)

    # 7. Extract each table
    for table_config in tables_to_extract:
        table_name = table_config["name"]
        limit = table_config.get("limit")

        # Extract data
        df = pipeline.extract_table(
            table_name=table_name,
            limit=limit
        )

        # Write to Bronze storage
        # Framework handles path creation and format conversion
        paths = pipeline.write_bronze(
            df,
            source_system="pagila_example",
            table_name=table_name,
            formats=["parquet", "json"]  # Multiple formats
        )

        print(f"✓ Wrote {table_name} to Bronze:")
        print(f"    Parquet: {paths['parquet']}")
        print(f"    JSON: {paths['json']}")
        print()

    # 8. Summary
    print("=" * 60)
    print("Extraction Complete!")
    print(f"Bronze data written to: {bronze_path}")
    print("\nKey Takeaways:")
    print("1. Framework handled all connection complexity")
    print("2. BronzeMetadata was added automatically")
    print("3. Data written in multiple formats with one call")
    print("4. No manual resource cleanup needed")
    print("=" * 60)


if __name__ == "__main__":
    main()