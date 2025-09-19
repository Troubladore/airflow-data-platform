#!/bin/bash
# Data Quality Validation Script
# Validates data integrity across the bronze → silver → gold pipeline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DB="postgresql://postgres:postgres@localhost:5432/pagila"
TARGET_DB="postgresql://warehouse:warehouse@localhost:5433/data_warehouse"

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

print_banner() {
    echo -e "${BLUE}"
    echo "📊 =================================================="
    echo "   DATA QUALITY VALIDATION"
    echo "   Astronomer Airflow Platform"
    echo "==================================================${NC}"
    echo
    echo "This script validates:"
    echo "• Data freshness and completeness"
    echo "• Row count consistency across pipeline stages"
    echo "• Schema validation and data types"
    echo "• Business rule compliance"
    echo "• Data lineage and audit trail integrity"
    echo
}

# Database connectivity test
test_database_connectivity() {
    log_info "Testing database connectivity..."

    # Test source database
    if docker exec pagila-source pg_isready -U postgres >/dev/null 2>&1; then
        log_success "Source database (Pagila) is accessible"
    else
        log_error "Source database is not accessible"
        return 1
    fi

    # Test target database
    if docker exec data-warehouse pg_isready -U warehouse >/dev/null 2>&1; then
        log_success "Target database (Data Warehouse) is accessible"
    else
        log_error "Target database is not accessible"
        return 1
    fi
}

# Execute SQL query and return result
execute_sql() {
    local db_container="$1"
    local db_user="$2"
    local db_name="$3"
    local query="$4"

    docker exec "$db_container" psql -U "$db_user" -d "$db_name" -t -c "$query" 2>/dev/null | tr -d ' ' || echo "0"
}

# Validate row counts across pipeline stages
validate_row_counts() {
    log_info "Validating row counts across pipeline stages..."

    # Define tables to validate
    local tables=("actor" "film" "category" "customer")
    local validation_passed=true

    for table in "${tables[@]}"; do
        log_info "Validating $table pipeline..."

        # Get source row count
        local source_count=$(execute_sql "pagila-source" "postgres" "pagila" "SELECT COUNT(*) FROM public.\"$table\";")

        # Get bronze row count
        local bronze_count=$(execute_sql "data-warehouse" "warehouse" "data_warehouse" "SELECT COUNT(*) FROM bronze_pagila.br_$table;")

        # Get silver row count (if exists)
        local silver_count=$(execute_sql "data-warehouse" "warehouse" "data_warehouse" "SELECT COUNT(*) FROM silver_core.${table}_cleaned;")

        echo "  📊 $table pipeline:"
        echo "    Source:  $source_count rows"
        echo "    Bronze:  $bronze_count rows"
        echo "    Silver:  $silver_count rows"

        # Validate source → bronze (should match exactly)
        if [ "$source_count" -eq "$bronze_count" ] && [ "$source_count" -gt 0 ]; then
            log_success "  Source → Bronze: Row count matches ($source_count)"
        elif [ "$bronze_count" -eq 0 ]; then
            log_warning "  Source → Bronze: No data in bronze layer"
            validation_passed=false
        else
            log_error "  Source → Bronze: Row count mismatch (source: $source_count, bronze: $bronze_count)"
            validation_passed=false
        fi

        # Validate bronze → silver (may differ due to cleaning)
        if [ "$silver_count" -gt 0 ]; then
            local retention_rate=$(( (silver_count * 100) / bronze_count ))
            if [ "$retention_rate" -ge 95 ]; then
                log_success "  Bronze → Silver: Good retention rate (${retention_rate}%)"
            elif [ "$retention_rate" -ge 80 ]; then
                log_warning "  Bronze → Silver: Moderate retention rate (${retention_rate}%)"
            else
                log_error "  Bronze → Silver: Low retention rate (${retention_rate}%)"
                validation_passed=false
            fi
        else
            log_warning "  Bronze → Silver: No data in silver layer"
        fi

        echo
    done

    if [ "$validation_passed" = true ]; then
        log_success "Row count validation passed"
        return 0
    else
        log_error "Row count validation failed"
        return 1
    fi
}

# Validate data freshness
validate_data_freshness() {
    log_info "Validating data freshness..."

    local freshness_passed=true

    # Check bronze layer freshness (should be recent)
    local latest_load_time=$(execute_sql "data-warehouse" "warehouse" "data_warehouse" "
        SELECT EXTRACT(EPOCH FROM (NOW() - MAX(br_load_time)))/60
        FROM bronze_pagila.br_actor;
    ")

    if [ "${latest_load_time%.*}" -lt 60 ]; then
        log_success "Bronze layer data is fresh (${latest_load_time%.*} minutes old)"
    elif [ "${latest_load_time%.*}" -lt 1440 ]; then
        log_warning "Bronze layer data is moderate (${latest_load_time%.*} minutes old)"
    else
        log_error "Bronze layer data is stale (${latest_load_time%.*} minutes old)"
        freshness_passed=false
    fi

    # Check for batch consistency
    local batch_count=$(execute_sql "data-warehouse" "warehouse" "data_warehouse" "
        SELECT COUNT(DISTINCT br_batch_id) FROM bronze_pagila.br_actor;
    ")

    if [ "$batch_count" -gt 0 ]; then
        log_success "Found $batch_count distinct batch(es) in bronze layer"
    else
        log_error "No batch IDs found in bronze layer"
        freshness_passed=false
    fi

    if [ "$freshness_passed" = true ]; then
        log_success "Data freshness validation passed"
        return 0
    else
        log_error "Data freshness validation failed"
        return 1
    fi
}

# Validate data quality rules
validate_data_quality_rules() {
    log_info "Validating data quality rules..."

    local quality_passed=true

    # Check for null values in key columns
    local null_check_queries=(
        "SELECT COUNT(*) FROM bronze_pagila.br_actor WHERE actor_id IS NULL;"
        "SELECT COUNT(*) FROM bronze_pagila.br_film WHERE film_id IS NULL;"
        "SELECT COUNT(*) FROM bronze_pagila.br_customer WHERE customer_id IS NULL;"
    )

    for query in "${null_check_queries[@]}"; do
        local null_count=$(execute_sql "data-warehouse" "warehouse" "data_warehouse" "$query")
        local table_name=$(echo "$query" | sed -n 's/.*FROM bronze_pagila\.\(br_[^[:space:]]*\).*/\1/p')

        if [ "$null_count" -eq 0 ]; then
            log_success "No null IDs found in $table_name"
        else
            log_error "Found $null_count null IDs in $table_name"
            quality_passed=false
        fi
    done

    # Check audit column completeness
    local audit_completeness=$(execute_sql "data-warehouse" "warehouse" "data_warehouse" "
        SELECT COUNT(*) FROM bronze_pagila.br_actor
        WHERE br_load_time IS NULL
        OR br_source_table IS NULL
        OR br_batch_id IS NULL
        OR br_record_hash IS NULL;
    ")

    if [ "$audit_completeness" -eq 0 ]; then
        log_success "All audit columns are complete"
    else
        log_error "Found $audit_completeness incomplete audit records"
        quality_passed=false
    fi

    # Check for duplicate records
    local duplicate_count=$(execute_sql "data-warehouse" "warehouse" "data_warehouse" "
        SELECT COUNT(*) - COUNT(DISTINCT br_record_hash) FROM bronze_pagila.br_actor;
    ")

    if [ "$duplicate_count" -eq 0 ]; then
        log_success "No duplicate records found"
    else
        log_warning "Found $duplicate_count potential duplicate records"
    fi

    if [ "$quality_passed" = true ]; then
        log_success "Data quality validation passed"
        return 0
    else
        log_error "Data quality validation failed"
        return 1
    fi
}

# Validate schema consistency
validate_schema_consistency() {
    log_info "Validating schema consistency..."

    local schema_passed=true

    # Check that all expected schemas exist
    local expected_schemas=("bronze_pagila" "silver_core" "gold_analytics")

    for schema in "${expected_schemas[@]}"; do
        local schema_exists=$(execute_sql "data-warehouse" "warehouse" "data_warehouse" "
            SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = '$schema';
        ")

        if [ "$schema_exists" -eq 1 ]; then
            log_success "Schema $schema exists"
        else
            log_error "Schema $schema is missing"
            schema_passed=false
        fi
    done

    # Check that bronze tables have audit columns
    local bronze_tables=$(execute_sql "data-warehouse" "warehouse" "data_warehouse" "
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'bronze_pagila' AND table_type = 'BASE TABLE';
    " | tr '\n' ' ')

    for table in $bronze_tables; do
        local audit_columns=$(execute_sql "data-warehouse" "warehouse" "data_warehouse" "
            SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema = 'bronze_pagila'
            AND table_name = '$table'
            AND column_name IN ('br_load_time', 'br_source_table', 'br_batch_id', 'br_is_current', 'br_record_hash');
        ")

        if [ "$audit_columns" -eq 5 ]; then
            log_success "Table $table has all audit columns"
        else
            log_error "Table $table missing audit columns (found $audit_columns/5)"
            schema_passed=false
        fi
    done

    if [ "$schema_passed" = true ]; then
        log_success "Schema validation passed"
        return 0
    else
        log_error "Schema validation failed"
        return 1
    fi
}

# Generate data quality report
generate_data_quality_report() {
    log_info "Generating data quality report..."

    local report_file="/tmp/data_quality_report_$(date +%Y%m%d_%H%M%S).txt"

    cat > "$report_file" << EOF
# Data Quality Report
Generated: $(date)

## Summary Statistics
EOF

    # Add row count summary
    echo "## Row Counts by Layer" >> "$report_file"
    local tables=("actor" "film" "category" "customer")

    for table in "${tables[@]}"; do
        local source_count=$(execute_sql "pagila-source" "postgres" "pagila" "SELECT COUNT(*) FROM public.\"$table\";")
        local bronze_count=$(execute_sql "data-warehouse" "warehouse" "data_warehouse" "SELECT COUNT(*) FROM bronze_pagila.br_$table;")
        local silver_count=$(execute_sql "data-warehouse" "warehouse" "data_warehouse" "SELECT COUNT(*) FROM silver_core.${table}_cleaned;")

        echo "- $table: Source=$source_count, Bronze=$bronze_count, Silver=$silver_count" >> "$report_file"
    done

    # Add freshness information
    echo "" >> "$report_file"
    echo "## Data Freshness" >> "$report_file"
    local latest_batch=$(execute_sql "data-warehouse" "warehouse" "data_warehouse" "
        SELECT MAX(br_batch_id) FROM bronze_pagila.br_actor;
    ")
    local latest_load=$(execute_sql "data-warehouse" "warehouse" "data_warehouse" "
        SELECT MAX(br_load_time) FROM bronze_pagila.br_actor;
    ")

    echo "- Latest batch: $latest_batch" >> "$report_file"
    echo "- Latest load: $latest_load" >> "$report_file"

    log_success "Data quality report generated: $report_file"

    if [ "${VERBOSE:-false}" = true ]; then
        echo
        echo -e "${BLUE}📋 Data Quality Report:${NC}"
        cat "$report_file"
    fi
}

# Parse command line arguments
VERBOSE=false
TABLES=""
SKIP_CONNECTIVITY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --tables)
            TABLES="$2"
            shift 2
            ;;
        --skip-connectivity)
            SKIP_CONNECTIVITY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --verbose            Show detailed output and report"
            echo "  --tables TABLES      Comma-separated list of tables to validate"
            echo "  --skip-connectivity  Skip database connectivity tests"
            echo "  -h, --help          Show this help"
            exit 0
            ;;
        *)
            log_warning "Unknown option: $1"
            shift
            ;;
    esac
done

# Main execution
main() {
    print_banner

    local validation_passed=true

    # Database connectivity
    if [ "$SKIP_CONNECTIVITY" = false ]; then
        test_database_connectivity || validation_passed=false
    fi

    # Core validations
    validate_row_counts || validation_passed=false
    validate_data_freshness || validation_passed=false
    validate_data_quality_rules || validation_passed=false
    validate_schema_consistency || validation_passed=false

    # Generate report
    generate_data_quality_report

    # Final summary
    echo
    if [ "$validation_passed" = true ]; then
        log_success "🎉 All data quality validations passed!"
        echo
        echo -e "${GREEN}Your data pipeline is healthy:${NC}"
        echo "✅ Data freshness is good"
        echo "✅ Row counts are consistent"
        echo "✅ Data quality rules are met"
        echo "✅ Schema is properly structured"
        echo
        echo -e "${BLUE}Next Steps:${NC}"
        echo "• Run analytics queries on gold layer"
        echo "• Connect BI tools to data warehouse"
        echo "• Set up monitoring and alerting"
        echo
        return 0
    else
        log_error "❌ Data quality validation failed!"
        echo
        echo -e "${RED}Issues detected in your data pipeline:${NC}"
        echo "Please review the errors above and:"
        echo "1. Check data processing logs"
        echo "2. Verify database connectivity"
        echo "3. Re-run pipeline with fresh data"
        echo "4. Examine DBT transformation logic"
        echo
        return 1
    fi
}

# Handle script errors
trap 'log_error "Data quality validation failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"
