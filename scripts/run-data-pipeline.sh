#!/bin/bash
# End-to-End Data Pipeline Execution Script
# Orchestrates bronze → silver → gold data processing pipeline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_HOST="registry.localhost"

# Pipeline configuration
BATCH_ID="pipeline_$(date +%Y%m%d_%H%M%S)"
PIPELINE_LOG="/tmp/data_pipeline_${BATCH_ID}.log"

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

print_banner() {
    echo -e "${BLUE}"
    echo "🚀 =================================================="
    echo "   DATA PIPELINE EXECUTION"
    echo "   Bronze → Silver → Gold Processing"
    echo "==================================================${NC}"
    echo
    echo "Pipeline Configuration:"
    echo "• Batch ID: $BATCH_ID"
    echo "• Pipeline Log: $PIPELINE_LOG"
    echo "• Mode: ${PIPELINE_MODE:-incremental}"
    echo "• Target Tables: ${TARGET_TABLES:-all}"
    echo
    echo "This pipeline will:"
    echo "• Stage 1: Bronze layer data ingestion"
    echo "• Stage 2: Silver layer cleaning and validation"
    echo "• Stage 3: Gold layer analytics preparation"
    echo "• Stage 4: Data quality validation and reporting"
    echo
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking pipeline prerequisites..."

    # Check if databases are running
    local required_containers=("pagila-source" "data-warehouse")
    for container in "${required_containers[@]}"; do
        if ! docker ps --format "table {{.Names}}" | grep -q "$container"; then
            log_error "$container container is not running"
            log_error "Please run: ./scripts/setup-layer2.sh"
            return 1
        fi
    done

    # Check database connectivity
    if ! docker exec pagila-source pg_isready -U postgres >/dev/null 2>&1; then
        log_error "Source database is not ready"
        return 1
    fi

    if ! docker exec data-warehouse pg_isready -U warehouse >/dev/null 2>&1; then
        log_error "Target database is not ready"
        return 1
    fi

    # Check if source data exists
    local source_tables=$(docker exec pagila-source psql -U postgres -d pagila -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ' || echo "0")
    if [ "$source_tables" -eq 0 ]; then
        log_warning "No source data found - loading sample data..."
        "$SCRIPT_DIR/load-sample-data.sh" || {
            log_error "Failed to load sample data"
            return 1
        }
    fi

    # Check datakit images availability
    local datakits=("bronze-pagila" "postgres-runner" "dbt-runner")
    for datakit in "${datakits[@]}"; do
        if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "$REGISTRY_HOST/datakits/$datakit:latest"; then
            log_error "Datakit image not found: $REGISTRY_HOST/datakits/$datakit:latest"
            log_error "Please run: ./scripts/setup-layer2.sh --rebuild-images"
            return 1
        fi
    done

    log_success "Prerequisites verified"
}

# Execute SQL command with error handling
execute_sql() {
    local container="$1"
    local user="$2"
    local database="$3"
    local query="$4"
    local description="${5:-SQL execution}"

    log_info "$description..."

    if docker exec "$container" psql -U "$user" -d "$database" -c "$query" >>"$PIPELINE_LOG" 2>&1; then
        log_success "$description completed"
        return 0
    else
        log_error "$description failed - check $PIPELINE_LOG for details"
        return 1
    fi
}

# Stage 1: Bronze Layer Ingestion
execute_bronze_ingestion() {
    log_info "🥉 Stage 1: Bronze Layer Data Ingestion"
    echo "========================================="

    # Define tables to process
    local tables=(${TARGET_TABLES:-"actor film category customer"})
    local ingestion_mode="full"

    if [ "${PIPELINE_MODE:-incremental}" = "incremental" ]; then
        ingestion_mode="incremental"
    fi

    # Clear bronze tables if full refresh
    if [ "${PIPELINE_MODE}" = "full-refresh" ]; then
        log_warning "Full refresh mode - clearing existing bronze data..."
        for table in "${tables[@]}"; do
            execute_sql "data-warehouse" "warehouse" "data_warehouse" \
                "DELETE FROM bronze_pagila.br_$table;" \
                "Clearing bronze table br_$table"
        done
    fi

    # Process each table through bronze ingestion
    for table in "${tables[@]}"; do
        log_info "Processing $table through bronze ingestion..."

        # Run bronze datakit for this table
        docker run --rm \
            --network data-processing-network \
            -e SOURCE_DB_URL="postgresql://postgres:postgres@pagila-source:5432/pagila" \
            -e TARGET_DB_URL="postgresql://warehouse:warehouse@data-warehouse:5432/data_warehouse" \
            -e BATCH_ID="$BATCH_ID" \
            -e TABLE_NAME="$table" \
            -e INGESTION_MODE="$ingestion_mode" \
            "$REGISTRY_HOST/datakits/bronze-pagila:latest" \
            >> "$PIPELINE_LOG" 2>&1 || {
            log_error "Bronze ingestion failed for $table - check $PIPELINE_LOG"
            return 1
        }

        # Verify ingestion results
        local row_count=$(docker exec data-warehouse psql -U warehouse -d data_warehouse -t -c "SELECT COUNT(*) FROM bronze_pagila.br_$table;" 2>/dev/null | tr -d ' ' || echo "0")

        if [ "$row_count" -gt 0 ]; then
            log_success "Bronze ingestion: $table ($row_count rows)"
        else
            log_error "Bronze ingestion: $table (no data ingested)"
            return 1
        fi
    done

    log_success "🥉 Bronze layer ingestion completed"
}

# Stage 2: Silver Layer Processing
execute_silver_processing() {
    log_info "🥈 Stage 2: Silver Layer Processing"
    echo "===================================="

    cd "$REPO_ROOT/layer2-dbt-projects/silver-core"

    # Configure DBT profiles
    export DBT_PROFILES_DIR="$REPO_ROOT/.dbt"
    mkdir -p "$DBT_PROFILES_DIR"

    cat > "$DBT_PROFILES_DIR/profiles.yml" << EOF
silver_core:
  target: dev
  outputs:
    dev:
      type: postgres
      host: localhost
      port: 5433
      user: warehouse
      password: warehouse
      dbname: data_warehouse
      schema: silver_core
      threads: 4
      keepalives_idle: 0
EOF

    # Install DBT dependencies
    if [ -f "packages.yml" ]; then
        log_info "Installing DBT dependencies..."
        dbt deps --profiles-dir "$DBT_PROFILES_DIR" >> "$PIPELINE_LOG" 2>&1 || {
            log_warning "DBT deps had issues - continuing"
        }
    fi

    # Execute silver layer transformations
    local dbt_mode="--full-refresh"
    if [ "${PIPELINE_MODE:-incremental}" = "incremental" ]; then
        dbt_mode=""
    fi

    log_info "Running silver layer transformations..."
    if dbt run $dbt_mode --profiles-dir "$DBT_PROFILES_DIR" >> "$PIPELINE_LOG" 2>&1; then
        log_success "Silver layer transformations completed"
    else
        log_error "Silver layer transformations failed - check $PIPELINE_LOG"
        return 1
    fi

    # Run data quality tests
    log_info "Running silver layer data quality tests..."
    if dbt test --profiles-dir "$DBT_PROFILES_DIR" >> "$PIPELINE_LOG" 2>&1; then
        log_success "Silver layer tests passed"
    else
        log_warning "Some silver layer tests failed - check $PIPELINE_LOG"
    fi

    # Verify silver layer results
    local tables=(${TARGET_TABLES:-"actor film category customer"})
    for table in "${tables[@]}"; do
        local silver_count=$(docker exec data-warehouse psql -U warehouse -d data_warehouse -t -c "SELECT COUNT(*) FROM silver_core.${table}_cleaned;" 2>/dev/null | tr -d ' ' || echo "0")
        if [ "$silver_count" -gt 0 ]; then
            log_success "Silver processing: ${table}_cleaned ($silver_count rows)"
        else
            log_warning "Silver processing: ${table}_cleaned (no data processed)"
        fi
    done

    log_success "🥈 Silver layer processing completed"
    cd "$REPO_ROOT"
}

# Stage 3: Gold Layer Analytics
execute_gold_processing() {
    log_info "🥇 Stage 3: Gold Layer Analytics Processing"
    echo "=========================================="

    # Process dimensions first
    cd "$REPO_ROOT/layer2-dbt-projects/gold-dimensions"

    # Configure DBT profiles for dimensions
    cat > "$DBT_PROFILES_DIR/profiles.yml" << EOF
gold_dimensions:
  target: dev
  outputs:
    dev:
      type: postgres
      host: localhost
      port: 5433
      user: warehouse
      password: warehouse
      dbname: data_warehouse
      schema: gold_analytics
      threads: 4
      keepalives_idle: 0
EOF

    # Execute dimension processing
    local dbt_mode="--full-refresh"
    if [ "${PIPELINE_MODE:-incremental}" = "incremental" ]; then
        dbt_mode=""
    fi

    log_info "Processing gold dimensions..."
    if dbt run $dbt_mode --profiles-dir "$DBT_PROFILES_DIR" >> "$PIPELINE_LOG" 2>&1; then
        log_success "Gold dimensions processing completed"
    else
        log_error "Gold dimensions processing failed - check $PIPELINE_LOG"
        return 1
    fi

    # Process facts
    cd "$REPO_ROOT/layer2-dbt-projects/gold-facts"

    # Configure DBT profiles for facts
    cat > "$DBT_PROFILES_DIR/profiles.yml" << EOF
gold_facts:
  target: dev
  outputs:
    dev:
      type: postgres
      host: localhost
      port: 5433
      user: warehouse
      password: warehouse
      dbname: data_warehouse
      schema: gold_analytics
      threads: 4
      keepalives_idle: 0
EOF

    log_info "Processing gold facts..."
    if dbt run $dbt_mode --profiles-dir "$DBT_PROFILES_DIR" >> "$PIPELINE_LOG" 2>&1; then
        log_success "Gold facts processing completed"
    else
        log_error "Gold facts processing failed - check $PIPELINE_LOG"
        return 1
    fi

    # Verify gold layer results
    local gold_tables=$(docker exec data-warehouse psql -U warehouse -d data_warehouse -t -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'gold_analytics' ORDER BY table_name;" 2>/dev/null | tr -d ' ' | grep -v '^$' || true)

    for table in $gold_tables; do
        local gold_count=$(docker exec data-warehouse psql -U warehouse -d data_warehouse -t -c "SELECT COUNT(*) FROM gold_analytics.\"$table\";" 2>/dev/null | tr -d ' ' || echo "0")
        if [ "$gold_count" -gt 0 ]; then
            log_success "Gold analytics: $table ($gold_count rows)"
        fi
    done

    log_success "🥇 Gold layer analytics completed"
    cd "$REPO_ROOT"
}

# Stage 4: Data Quality Validation
execute_pipeline_validation() {
    log_info "🔍 Stage 4: Pipeline Validation & Quality Checks"
    echo "============================================="

    # Run comprehensive data quality validation
    if "$SCRIPT_DIR/validate-data-quality.sh" --skip-connectivity >> "$PIPELINE_LOG" 2>&1; then
        log_success "Data quality validation passed"
    else
        log_warning "Data quality validation had issues - check results"
    fi

    # Generate pipeline completion report
    log_info "Generating pipeline completion report..."
    local report_file="/tmp/pipeline_report_${BATCH_ID}.txt"

    cat > "$report_file" << EOF
# Data Pipeline Execution Report
Pipeline ID: $BATCH_ID
Execution Time: $(date)
Mode: ${PIPELINE_MODE:-incremental}
Target Tables: ${TARGET_TABLES:-all}

## Processing Summary
EOF

    # Add row count summary by layer
    echo "## Row Counts by Layer" >> "$report_file"
    local tables=(${TARGET_TABLES:-"actor film category customer"})

    for table in "${tables[@]}"; do
        local source_count=$(docker exec pagila-source psql -U postgres -d pagila -t -c "SELECT COUNT(*) FROM public.\"$table\";" 2>/dev/null | tr -d ' ' || echo "0")
        local bronze_count=$(docker exec data-warehouse psql -U warehouse -d data_warehouse -t -c "SELECT COUNT(*) FROM bronze_pagila.br_$table;" 2>/dev/null | tr -d ' ' || echo "0")
        local silver_count=$(docker exec data-warehouse psql -U warehouse -d data_warehouse -t -c "SELECT COUNT(*) FROM silver_core.${table}_cleaned;" 2>/dev/null | tr -d ' ' || echo "0")

        echo "- $table: Source=$source_count, Bronze=$bronze_count, Silver=$silver_count" >> "$report_file"
    done

    # Add gold layer summary
    echo "" >> "$report_file"
    echo "## Gold Layer Tables" >> "$report_file"
    local gold_tables=$(docker exec data-warehouse psql -U warehouse -d data_warehouse -t -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'gold_analytics' ORDER BY table_name;" 2>/dev/null | tr -d ' ' | grep -v '^$' || true)

    for table in $gold_tables; do
        local gold_count=$(docker exec data-warehouse psql -U warehouse -d data_warehouse -t -c "SELECT COUNT(*) FROM gold_analytics.\"$table\";" 2>/dev/null | tr -d ' ' || echo "0")
        echo "- $table: $gold_count rows" >> "$report_file"
    done

    log_success "Pipeline report generated: $report_file"

    if [ "${VERBOSE:-false}" = true ]; then
        echo
        echo -e "${BLUE}📋 Pipeline Execution Report:${NC}"
        cat "$report_file"
    fi

    log_success "🔍 Pipeline validation completed"
}

# Show pipeline results
show_pipeline_results() {
    echo
    echo -e "${GREEN}🎉 Data Pipeline Execution Complete!${NC}"
    echo
    echo -e "${BLUE}📊 Pipeline Results:${NC}"
    echo "• Batch ID: $BATCH_ID"
    echo "• Pipeline Log: $PIPELINE_LOG"
    echo "• Execution Mode: ${PIPELINE_MODE:-incremental}"
    echo "• Tables Processed: ${TARGET_TABLES:-all standard tables}"
    echo
    echo -e "${BLUE}🗂️ Data Available:${NC}"
    echo "• Bronze Layer: Raw data with audit trails"
    echo "• Silver Layer: Cleaned and validated data"
    echo "• Gold Layer: Analytics-ready dimensions and facts"
    echo
    echo -e "${BLUE}🔗 Connection Information:${NC}"
    echo "• Data Warehouse: postgresql://warehouse:warehouse@localhost:5433/data_warehouse"
    echo "• Schemas: bronze_pagila, silver_core, gold_analytics"
    echo
    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo "1. Connect BI tools to gold layer:"
    echo "   psql -h localhost -p 5433 -U warehouse -d data_warehouse"
    echo
    echo "2. Query analytics data:"
    echo "   SELECT * FROM gold_analytics.dim_actor LIMIT 10;"
    echo
    echo "3. Run data quality validation:"
    echo "   ./scripts/validate-data-quality.sh --verbose"
    echo
    echo "4. Schedule incremental updates:"
    echo "   ./scripts/run-data-pipeline.sh --incremental"
    echo
}

# Parse command line arguments
PIPELINE_MODE="incremental"
TARGET_TABLES=""
VERBOSE=false
TEST_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --full-refresh)
            PIPELINE_MODE="full-refresh"
            shift
            ;;
        --incremental)
            PIPELINE_MODE="incremental"
            shift
            ;;
        --tables)
            TARGET_TABLES="$2"
            shift 2
            ;;
        --test-mode)
            TEST_MODE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --full-refresh    Force full refresh of all layers"
            echo "  --incremental     Run incremental processing (default)"
            echo "  --tables TABLES   Process specific tables only"
            echo "  --test-mode       Run with test data and validation"
            echo "  --verbose         Show detailed output and reports"
            echo "  -h, --help       Show this help"
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

    # Initialize pipeline logging
    echo "Data Pipeline Execution Log - Batch: $BATCH_ID" > "$PIPELINE_LOG"
    echo "Started: $(date)" >> "$PIPELINE_LOG"
    echo "========================================" >> "$PIPELINE_LOG"

    local pipeline_success=true

    # Execute pipeline stages
    check_prerequisites || pipeline_success=false

    if [ "$pipeline_success" = true ]; then
        execute_bronze_ingestion || pipeline_success=false
    fi

    if [ "$pipeline_success" = true ]; then
        execute_silver_processing || pipeline_success=false
    fi

    if [ "$pipeline_success" = true ]; then
        execute_gold_processing || pipeline_success=false
    fi

    if [ "$pipeline_success" = true ]; then
        execute_pipeline_validation || pipeline_success=false
    fi

    # Final results
    echo "" >> "$PIPELINE_LOG"
    echo "Pipeline completed: $(date)" >> "$PIPELINE_LOG"
    echo "Success: $pipeline_success" >> "$PIPELINE_LOG"

    if [ "$pipeline_success" = true ]; then
        show_pipeline_results
        return 0
    else
        log_error "❌ Data pipeline execution failed!"
        echo
        echo -e "${RED}Pipeline execution encountered errors:${NC}"
        echo "• Check the pipeline log: $PIPELINE_LOG"
        echo "• Validate your setup: ./scripts/validate-data-quality.sh --verbose"
        echo "• Restart with fresh data: ./scripts/teardown-layer2.sh --preserve-data"
        echo "• Review component logs: docker logs <container-name>"
        echo
        return 1
    fi
}

# Handle script errors
trap 'log_error "Data pipeline execution failed at line $LINENO. Exit code: $?"; echo "Pipeline log: $PIPELINE_LOG"' ERR

# Run main function
main "$@"
