#!/usr/bin/env python3
"""
Kerberos Bronze layer extraction example using SQLModel Framework.

This script demonstrates enterprise authentication with Kerberos/GSSAPI
for secure, password-free database connections.
"""

import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, Any
import pandas as pd
from dotenv import load_dotenv

# Import framework components
from sqlmodel_framework.base.connectors import PostgresConnector, PostgresConfig
from sqlmodel_framework.base.loaders import BronzeIngestionPipeline

# Load environment variables
load_dotenv()


class KerberosBronzePipeline(BronzeIngestionPipeline):
    """
    Bronze ingestion pipeline with Kerberos authentication.

    This pipeline demonstrates enterprise-grade authentication
    without passwords in code.
    """

    def __init__(self, connector: PostgresConnector, bronze_path: Path):
        """Initialize with additional Kerberos info."""
        super().__init__(connector, bronze_path)
        self.extraction_timestamp = datetime.utcnow()

    def extract_table(
        self,
        table_name: str,
        schema: str = "public",
        limit: Optional[int] = None
    ) -> pd.DataFrame:
        """
        Extract data from source table with full schema qualification.

        Args:
            table_name: Name of the table to extract
            schema: Schema name (default: public)
            limit: Optional row limit for testing

        Returns:
            DataFrame with extracted data and Bronze metadata
        """
        # Build fully-qualified table name
        qualified_table = f"{schema}.{table_name}"

        # Build query
        query = f"SELECT * FROM {qualified_table}"
        if limit:
            query += f" LIMIT {limit}"

        print(f"Extracting from {qualified_table}...")

        # Execute query with Kerberos authentication
        # No passwords needed - uses Kerberos ticket!
        with self.connector.connection_context() as conn:
            df = pd.read_sql(query, conn)

        print(f"  ✓ Extracted {len(df)} rows")

        # Add Bronze metadata
        df = self.add_bronze_metadata(
            df,
            source_system="enterprise_postgres",
            source_table=qualified_table,
            source_host=self.connector.config.host,
            extraction_method="kerberos_snapshot"
        )

        return df

    def verify_kerberos_auth(self) -> Dict[str, Any]:
        """
        Verify Kerberos authentication is working.

        Returns:
            Dictionary with authentication details
        """
        auth_info = {}

        # Check for Kerberos ticket
        try:
            result = subprocess.run(
                ["klist"],
                capture_output=True,
                text=True,
                check=False
            )
            auth_info["has_ticket"] = result.returncode == 0
            auth_info["ticket_output"] = result.stdout if result.returncode == 0 else None

            # Extract principal from ticket
            if auth_info["has_ticket"] and result.stdout:
                for line in result.stdout.split("\n"):
                    if "Default principal:" in line:
                        auth_info["principal"] = line.split(":")[-1].strip()
                        break
        except FileNotFoundError:
            auth_info["has_ticket"] = False
            auth_info["error"] = "klist command not found"

        # Test database connection
        auth_info["db_connection"] = self.connector.test_connection()

        # Get connection user from database
        if auth_info["db_connection"]:
            try:
                with self.connector.connection_context() as conn:
                    cursor = conn.cursor()
                    cursor.execute("SELECT current_user, session_user")
                    current_user, session_user = cursor.fetchone()
                    auth_info["db_user"] = current_user
                    auth_info["session_user"] = session_user
            except Exception as e:
                auth_info["db_error"] = str(e)

        return auth_info


def check_kerberos_environment():
    """
    Check if Kerberos environment is properly configured.
    """
    print("\n" + "=" * 60)
    print("Kerberos Environment Check")
    print("=" * 60)

    checks = []

    # Check for Kerberos ticket
    try:
        result = subprocess.run(
            ["klist"],
            capture_output=True,
            text=True,
            check=False
        )
        if result.returncode == 0:
            checks.append("✓ Kerberos ticket found")
            # Extract principal
            for line in result.stdout.split("\n"):
                if "Default principal:" in line:
                    principal = line.split(":")[-1].strip()
                    checks.append(f"  Principal: {principal}")
                elif "Valid starting" in line and "Expires" in line:
                    # Next line has ticket details
                    continue
                elif "krbtgt" in line:
                    parts = line.split()
                    if len(parts) >= 3:
                        checks.append(f"  Expires: {parts[1]} {parts[2]}")
        else:
            checks.append("✗ No Kerberos ticket (run 'kinit')")
            return False
    except FileNotFoundError:
        checks.append("✗ Kerberos not installed (klist not found)")
        return False

    # Check KRB5 environment variables
    krb5_config = os.environ.get("KRB5_CONFIG")
    if krb5_config:
        checks.append(f"  KRB5_CONFIG: {krb5_config}")

    krb5_trace = os.environ.get("KRB5_TRACE")
    if krb5_trace:
        checks.append(f"  KRB5_TRACE: {krb5_trace} (debug enabled)")

    for check in checks:
        print(check)

    return "✗" not in " ".join(checks)


def main():
    """
    Main extraction workflow with Kerberos authentication.
    """
    print("=" * 60)
    print("Kerberos Bronze Extraction Example")
    print("=" * 60)

    # 1. Check Kerberos environment
    if not check_kerberos_environment():
        print("\nERROR: Kerberos environment not ready")
        print("Run: kinit username@REALM.COM")
        sys.exit(1)

    # 2. Configure database connection with Kerberos
    # NO PASSWORDS IN CODE!
    config = PostgresConfig(
        host=os.getenv("DB_HOST", "pgserver.example.com"),
        port=int(os.getenv("DB_PORT", 5432)),
        database=os.getenv("DB_NAME", "analytics"),
        use_kerberos=True,  # Enable Kerberos authentication
        gssencmode=os.getenv("GSS_ENC_MODE", "prefer")  # GSSAPI encryption
    )

    print(f"\nConnecting to {config.host}:{config.port}/{config.database}")
    print(f"  Authentication: Kerberos/GSSAPI")
    print(f"  Encryption: {config.gssencmode}")

    # 3. Create connector - framework handles Kerberos complexity
    connector = PostgresConnector(config)

    # 4. Create Bronze pipeline
    bronze_path = Path("/tmp/bronze/kerberos_example")
    bronze_path.mkdir(parents=True, exist_ok=True)

    pipeline = KerberosBronzePipeline(
        connector=connector,
        bronze_path=bronze_path
    )

    # 5. Verify authentication
    print("\nVerifying Kerberos authentication...")
    auth_info = pipeline.verify_kerberos_auth()

    if not auth_info.get("db_connection"):
        print("✗ Failed to connect with Kerberos")
        if "error" in auth_info:
            print(f"  Error: {auth_info['error']}")
        sys.exit(1)

    print("✓ Connected with Kerberos!")
    print(f"  Database user: {auth_info.get('db_user', 'unknown')}")
    if auth_info.get("principal"):
        print(f"  Kerberos principal: {auth_info['principal']}")

    # 6. List available schemas and tables
    try:
        with connector.connection_context() as conn:
            cursor = conn.cursor()

            # Get schemas
            cursor.execute("""
                SELECT schema_name
                FROM information_schema.schemata
                WHERE schema_name NOT IN ('pg_catalog', 'information_schema')
                ORDER BY schema_name
            """)
            schemas = [row[0] for row in cursor.fetchall()]
            print(f"\nAvailable schemas: {', '.join(schemas)}")

            # Get tables from public schema
            tables = connector.get_tables(schema="public")
            print(f"Tables in public schema: {len(tables)}")

    except Exception as e:
        print(f"Warning: Could not list schemas/tables: {e}")
        # Continue anyway for demo purposes

    # 7. Extract tables (with sample data limits for demo)
    tables_to_extract = [
        {"schema": "public", "name": "film", "limit": 50},
        {"schema": "public", "name": "actor", "limit": 25},
        {"schema": "public", "name": "customer", "limit": 10},
    ]

    print(f"\nExtracting {len(tables_to_extract)} tables to Bronze")
    print(f"Bronze path: {bronze_path}")
    print("-" * 60)

    extracted_count = 0
    for table_config in tables_to_extract:
        try:
            schema = table_config["schema"]
            table_name = table_config["name"]
            limit = table_config.get("limit")

            # Extract data
            df = pipeline.extract_table(
                table_name=table_name,
                schema=schema,
                limit=limit
            )

            # Write to Bronze storage
            paths = pipeline.write_bronze(
                df,
                source_system="enterprise_postgres",
                table_name=f"{schema}.{table_name}",
                formats=["parquet", "json"]
            )

            print(f"✓ Wrote {schema}.{table_name} to Bronze:")
            print(f"    Records: {len(df)}")
            print(f"    Parquet: {paths['parquet'].name}")
            print(f"    JSON: {paths['json'].name}")
            print()

            extracted_count += 1

        except Exception as e:
            print(f"✗ Failed to extract {schema}.{table_name}: {e}")
            print()

    # 8. Summary
    print("=" * 60)
    print("Kerberos Extraction Complete!")
    print(f"Successfully extracted: {extracted_count}/{len(tables_to_extract)} tables")
    print(f"Bronze data location: {bronze_path}")
    print("\nKey Security Benefits:")
    print("✓ No passwords in code or environment")
    print("✓ Authentication via Kerberos ticket")
    print("✓ Optional GSSAPI encryption")
    print("✓ Automatic principal extraction")
    print("=" * 60)


if __name__ == "__main__":
    # Optional: Enable Kerberos debugging
    if os.getenv("DEBUG_KERBEROS"):
        os.environ["KRB5_TRACE"] = "/dev/stderr"
        print("Kerberos trace enabled (KRB5_TRACE=/dev/stderr)")

    main()