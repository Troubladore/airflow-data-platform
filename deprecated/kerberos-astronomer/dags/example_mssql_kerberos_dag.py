"""
Example DAG demonstrating SQL Server Bronze ingestion with Kerberos Authentication

This DAG shows how to:
1. Connect to SQL Server using Kerberos/NT Authentication
2. Ingest data from source tables (Bronze layer)
3. Handle connection pooling and error recovery
4. Work with the Kerberos sidecar container
"""

# Import our custom Kerberos-enabled hook
import sys
from datetime import datetime, timedelta
from typing import Any

from airflow import DAG
from airflow.decorators import task

sys.path.append("/usr/local/airflow/plugins")
from mssql_kerberos_hook import MSSQLKerberosHook

default_args = {
    "owner": "data-platform",
    "depends_on_past": False,
    "email": ["data-team@company.com"],
    "email_on_failure": True,
    "email_on_retry": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    "mssql_kerberos_bronze_ingestion",
    default_args=default_args,
    description="Bronze layer ingestion from SQL Server using Kerberos",
    schedule_interval="@daily",
    start_date=datetime(2025, 1, 1),
    catchup=False,
    tags=["bronze", "sql-server", "kerberos"],
) as dag:

    @task
    def verify_kerberos_ticket() -> bool:
        """Verify that Kerberos ticket is available and valid."""
        import os
        import subprocess

        # Check if KRB5CCNAME is set
        krb5ccname = os.environ.get("KRB5CCNAME", "/krb5/cache/krb5cc")
        print(f"KRB5CCNAME: {krb5ccname}")

        # Check if ticket cache exists
        if not os.path.exists(krb5ccname):
            raise FileNotFoundError(f"Kerberos ticket cache not found: {krb5ccname}")

        # Verify ticket with klist
        result = subprocess.run(["klist", "-s"], capture_output=True, text=True)

        if result.returncode != 0:
            raise RuntimeError("No valid Kerberos ticket found")

        # Show ticket details
        result = subprocess.run(["klist"], capture_output=True, text=True)
        print("Current Kerberos tickets:")
        print(result.stdout)

        return True

    @task
    def test_mssql_connection() -> dict[str, Any]:
        """Test SQL Server connection with Kerberos."""
        hook = MSSQLKerberosHook(mssql_conn_id="mssql_kerberos")

        success, message = hook.test_connection()
        if not success:
            raise ConnectionError(f"SQL Server connection failed: {message}")

        print(f"Connection test successful: {message}")

        # Get database metadata
        result = hook.run("""
            SELECT
                DB_NAME() as database_name,
                SUSER_NAME() as login_name,
                USER_NAME() as user_name,
                @@SERVERNAME as server_name,
                @@VERSION as server_version
        """)

        metadata = {
            "database": result[0][0],
            "login": result[0][1],
            "user": result[0][2],
            "server": result[0][3],
            "version": result[0][4][:100],  # Truncate long version string
        }

        print(f"Connected as: {metadata['login']} to {metadata['database']}")
        return metadata

    @task
    def list_source_tables() -> list[str]:
        """List available tables for ingestion."""
        hook = MSSQLKerberosHook(mssql_conn_id="mssql_kerberos")

        query = """
            SELECT
                SCHEMA_NAME(schema_id) + '.' + name as table_name
            FROM sys.tables
            WHERE is_ms_shipped = 0
            ORDER BY name
        """

        results = hook.run(query)
        tables = [row[0] for row in results]

        print(f"Found {len(tables)} tables for potential ingestion")
        for table in tables[:10]:  # Show first 10
            print(f"  - {table}")

        return tables

    @task
    def ingest_table_to_bronze(table_name: str, target_schema: str = "bronze") -> dict[str, Any]:
        """
        Ingest a table from SQL Server to Bronze layer.

        This would typically write to your data lake or staging database.
        """
        hook = MSSQLKerberosHook(mssql_conn_id="mssql_kerberos")

        # Get row count
        count_query = f"SELECT COUNT(*) FROM {table_name}"
        row_count = hook.run(count_query)[0][0]

        print(f"Ingesting {row_count} rows from {table_name}")

        # In production, you would:
        # 1. Read data in batches
        # 2. Write to your bronze layer (S3, ADLS, etc.)
        # 3. Track ingestion metadata

        # Example: Read first 1000 rows
        data_query = f"""
            SELECT TOP 1000 *
            FROM {table_name}
        """

        rows = hook.run(data_query)

        # Simulate writing to bronze layer
        ingestion_result = {
            "source_table": table_name,
            "target_schema": target_schema,
            "row_count": row_count,
            "sample_rows_read": len(rows),
            "ingestion_time": datetime.now().isoformat(),
            "status": "success",
        }

        print(f"Successfully ingested {table_name} to bronze layer")
        return ingestion_result

    @task
    def create_bronze_metadata_entry(ingestion_results: list[dict]) -> None:
        """Record ingestion metadata for data lineage."""
        hook = MSSQLKerberosHook(mssql_conn_id="mssql_kerberos")

        # Create metadata table if not exists
        create_table_sql = """
            IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'bronze_ingestion_log')
            CREATE TABLE bronze_ingestion_log (
                id INT IDENTITY(1,1) PRIMARY KEY,
                source_table NVARCHAR(255),
                target_schema NVARCHAR(50),
                row_count INT,
                ingestion_time DATETIME2,
                dag_run_id NVARCHAR(255),
                status NVARCHAR(50),
                created_at DATETIME2 DEFAULT GETDATE()
            )
        """

        hook.run(create_table_sql, autocommit=True)

        # Insert metadata
        for result in ingestion_results:
            insert_sql = """
                INSERT INTO bronze_ingestion_log
                (source_table, target_schema, row_count, ingestion_time, dag_run_id, status)
                VALUES (?, ?, ?, ?, ?, ?)
            """

            from airflow.operators.python import get_current_context

            context = get_current_context()

            params = (
                result["source_table"],
                result["target_schema"],
                result["row_count"],
                result["ingestion_time"],
                context["dag_run"].run_id,
                result["status"],
            )

            hook.run(insert_sql, parameters=params, autocommit=True)

        print(f"Recorded {len(ingestion_results)} ingestion metadata entries")

    # Task flow
    verify_ticket = verify_kerberos_ticket()
    test_conn = test_mssql_connection()
    tables = list_source_tables()

    # Ingest specific tables (in production, this would be dynamic)
    ingestion_results = []
    sample_tables = ["dbo.customers", "dbo.orders", "dbo.products"]

    for table in sample_tables:
        # Create dynamic task for each table
        ingest_task = ingest_table_to_bronze.override(task_id=f"ingest_{table.replace('.', '_')}")(
            table
        )
        ingestion_results.append(ingest_task)

    metadata_task = create_bronze_metadata_entry(ingestion_results)

    # Define dependencies
    verify_ticket >> test_conn >> tables >> ingestion_results >> metadata_task
