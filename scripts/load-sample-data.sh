#!/bin/bash
# Sample Data Loader Script
# Loads Pagila sample database for data processing testing

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

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

print_banner() {
    echo -e "${BLUE}"
    echo "📊 =================================================="
    echo "   SAMPLE DATA LOADER"
    echo "   Pagila Database for Testing"
    echo "==================================================${NC}"
    echo
    echo "This script will:"
    echo "• Download Pagila sample database schema and data"
    echo "• Load data into PostgreSQL source database"
    echo "• Verify data integrity and completeness"
    echo "• Prepare database for data processing pipeline"
    echo
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if source database container is running
    if ! docker ps --format "table {{.Names}}" | grep -q "pagila-source"; then
        log_error "Source database container 'pagila-source' is not running"
        log_error "Please run: ./scripts/setup-layer2.sh"
        exit 1
    fi

    # Check database connectivity
    if ! docker exec pagila-source pg_isready -U postgres >/dev/null 2>&1; then
        log_error "Source database is not ready"
        log_error "Wait a moment and try again, or restart with: docker restart pagila-source"
        exit 1
    fi

    log_success "Prerequisites verified"
}

# Download Pagila sample database files
download_pagila_files() {
    log_info "Downloading Pagila sample database files..."

    local temp_dir="/tmp/pagila_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    # Download schema and data files
    local pagila_files=(
        "https://raw.githubusercontent.com/devrimgunduz/pagila/master/pagila-schema.sql"
        "https://raw.githubusercontent.com/devrimgunduz/pagila/master/pagila-data.sql"
    )

    for file_url in "${pagila_files[@]}"; do
        local filename=$(basename "$file_url")
        log_info "Downloading $filename..."

        if command -v curl >/dev/null 2>&1; then
            curl -L -o "$filename" "$file_url" || {
                log_error "Failed to download $filename with curl"
                return 1
            }
        elif command -v wget >/dev/null 2>&1; then
            wget -O "$filename" "$file_url" || {
                log_error "Failed to download $filename with wget"
                return 1
            }
        else
            log_error "Neither curl nor wget available for downloads"
            return 1
        fi

        log_success "Downloaded $filename"
    done

    # Store temp directory path for cleanup
    echo "$temp_dir" > /tmp/pagila_temp_dir
    log_success "Pagila files downloaded to $temp_dir"
}

# Create inline Pagila schema and data (fallback)
create_inline_pagila_data() {
    log_info "Creating minimal Pagila sample data..."

    local temp_dir="/tmp/pagila_inline_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    # Create minimal schema
    cat > pagila-schema.sql << 'EOF'
-- Minimal Pagila Schema for Testing
CREATE TABLE actor (
    actor_id SERIAL PRIMARY KEY,
    first_name VARCHAR(45) NOT NULL,
    last_name VARCHAR(45) NOT NULL,
    last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE category (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(25) NOT NULL,
    last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE film (
    film_id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    release_year INTEGER,
    language_id INTEGER,
    rental_duration INTEGER DEFAULT 3,
    rental_rate DECIMAL(4,2) DEFAULT 4.99,
    length INTEGER,
    replacement_cost DECIMAL(5,2) DEFAULT 19.99,
    rating VARCHAR(10) DEFAULT 'G',
    last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE customer (
    customer_id SERIAL PRIMARY KEY,
    store_id INTEGER NOT NULL,
    first_name VARCHAR(45) NOT NULL,
    last_name VARCHAR(45) NOT NULL,
    email VARCHAR(50),
    address_id INTEGER NOT NULL,
    activebool BOOLEAN DEFAULT TRUE,
    create_date DATE DEFAULT CURRENT_DATE,
    last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    active INTEGER
);

-- Create indexes for performance
CREATE INDEX idx_actor_last_name ON actor(last_name);
CREATE INDEX idx_film_title ON film(title);
CREATE INDEX idx_customer_last_name ON customer(last_name);
EOF

    # Create minimal sample data
    cat > pagila-data.sql << 'EOF'
-- Minimal Sample Data for Testing
INSERT INTO actor (first_name, last_name) VALUES
    ('PENELOPE', 'GUINESS'),
    ('NICK', 'WAHLBERG'),
    ('ED', 'CHASE'),
    ('JENNIFER', 'DAVIS'),
    ('JOHNNY', 'LOLLOBRIGIDA'),
    ('BETTE', 'NICHOLSON'),
    ('GRACE', 'MOSTEL'),
    ('MATTHEW', 'JOHANSSON'),
    ('JOE', 'SWANK'),
    ('CHRISTIAN', 'GABLE');

INSERT INTO category (name) VALUES
    ('Action'),
    ('Animation'),
    ('Children'),
    ('Classics'),
    ('Comedy'),
    ('Documentary'),
    ('Drama'),
    ('Family'),
    ('Foreign'),
    ('Games');

INSERT INTO film (title, description, release_year, language_id, rental_duration, rental_rate, length, replacement_cost, rating) VALUES
    ('ACADEMY DINOSAUR', 'A Epic Drama of a Feminist And a Mad Scientist who must Battle a Teacher in The Canadian Rockies', 2006, 1, 6, 0.99, 86, 20.99, 'PG'),
    ('ACE GOLDFINGER', 'A Astounding Epistle of a Database Administrator And a Explorer who must Find a Car in Ancient China', 2006, 1, 3, 4.99, 48, 12.99, 'G'),
    ('ADAPTATION HOLES', 'A Astounding Reflection of a Lumberjack And a Car who must Sink a Lumberjack in A Baloon Factory', 2006, 1, 7, 2.99, 50, 18.99, 'NC-17'),
    ('AFFAIR PREJUDICE', 'A Fanciful Documentary of a Frisbee And a Lumberjack who must Chase a Monkey in A Shark Tank', 2006, 1, 5, 2.99, 117, 26.99, 'G'),
    ('AFRICAN EGG', 'A Fast-Paced Documentary of a Pastry Chef And a Dentist who must Pursue a Forensic Psychologist in The Gulf of Mexico', 2006, 1, 6, 2.99, 130, 22.99, 'G');

INSERT INTO customer (store_id, first_name, last_name, email, address_id, active) VALUES
    (1, 'MARY', 'SMITH', 'MARY.SMITH@sakilacustomer.org', 5, 1),
    (1, 'PATRICIA', 'JOHNSON', 'PATRICIA.JOHNSON@sakilacustomer.org', 6, 1),
    (1, 'LINDA', 'WILLIAMS', 'LINDA.WILLIAMS@sakilacustomer.org', 7, 1),
    (2, 'BARBARA', 'JONES', 'BARBARA.JONES@sakilacustomer.org', 8, 1),
    (2, 'ELIZABETH', 'BROWN', 'ELIZABETH.BROWN@sakilacustomer.org', 9, 1);
EOF

    echo "$temp_dir" > /tmp/pagila_temp_dir
    log_success "Inline Pagila data created in $temp_dir"
}

# Load data into database
load_pagila_database() {
    log_info "Loading Pagila database..."

    local temp_dir
    if [ -f /tmp/pagila_temp_dir ]; then
        temp_dir=$(cat /tmp/pagila_temp_dir)
    else
        log_error "Temp directory not found"
        return 1
    fi

    cd "$temp_dir"

    # Check if we have the schema file
    if [ ! -f "pagila-schema.sql" ]; then
        log_error "Schema file not found in $temp_dir"
        return 1
    fi

    # Load schema
    log_info "Loading database schema..."
    if docker exec -i pagila-source psql -U postgres -d pagila < pagila-schema.sql >/dev/null 2>&1; then
        log_success "Database schema loaded"
    else
        log_error "Failed to load database schema"
        return 1
    fi

    # Load data
    if [ -f "pagila-data.sql" ]; then
        log_info "Loading sample data..."
        if docker exec -i pagila-source psql -U postgres -d pagila < pagila-data.sql >/dev/null 2>&1; then
            log_success "Sample data loaded"
        else
            log_error "Failed to load sample data"
            return 1
        fi
    else
        log_warning "Data file not found, schema loaded without data"
    fi
}

# Verify data integrity
verify_data_integrity() {
    log_info "Verifying data integrity..."

    local verification_passed=true

    # Check table existence and row counts
    local expected_tables=("actor" "film" "category" "customer")
    local total_rows=0

    for table in "${expected_tables[@]}"; do
        local row_count=$(docker exec pagila-source psql -U postgres -d pagila -t -c "SELECT COUNT(*) FROM \"$table\";" 2>/dev/null | tr -d ' ' || echo "0")

        if [ "$row_count" -gt 0 ]; then
            log_success "$table: $row_count rows"
            total_rows=$((total_rows + row_count))
        else
            log_error "$table: No data found"
            verification_passed=false
        fi
    done

    # Check data types and constraints
    log_info "Checking data integrity constraints..."

    # Check for null primary keys
    local null_pks=0
    for table in "${expected_tables[@]}"; do
        local pk_column="${table}_id"
        local null_count=$(docker exec pagila-source psql -U postgres -d pagila -t -c "SELECT COUNT(*) FROM \"$table\" WHERE \"$pk_column\" IS NULL;" 2>/dev/null | tr -d ' ' || echo "0")
        null_pks=$((null_pks + null_count))
    done

    if [ "$null_pks" -eq 0 ]; then
        log_success "All primary keys are valid"
    else
        log_error "Found $null_pks null primary keys"
        verification_passed=false
    fi

    # Final verification
    if [ "$verification_passed" = true ] && [ "$total_rows" -gt 0 ]; then
        log_success "Data integrity verification passed ($total_rows total rows)"
        return 0
    else
        log_error "Data integrity verification failed"
        return 1
    fi
}

# Cleanup temporary files
cleanup_temp_files() {
    if [ -f /tmp/pagila_temp_dir ]; then
        local temp_dir=$(cat /tmp/pagila_temp_dir)
        if [ -d "$temp_dir" ]; then
            log_info "Cleaning up temporary files..."
            rm -rf "$temp_dir"
            rm -f /tmp/pagila_temp_dir
            log_success "Temporary files cleaned up"
        fi
    fi
}

# Show database information
show_database_info() {
    echo
    echo -e "${GREEN}🎉 Pagila Sample Database Loaded!${NC}"
    echo
    echo -e "${BLUE}📊 Database Information:${NC}"
    echo "• Host: localhost:5432"
    echo "• Database: pagila"
    echo "• Username: postgres"
    echo "• Password: postgres"
    echo "• Connection: postgresql://postgres:postgres@localhost:5432/pagila"
    echo
    echo -e "${BLUE}📋 Available Tables:${NC}"

    # Show table information
    local tables=$(docker exec pagila-source psql -U postgres -d pagila -t -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;" 2>/dev/null | tr -d ' ' | grep -v '^$' || true)

    for table in $tables; do
        local row_count=$(docker exec pagila-source psql -U postgres -d pagila -t -c "SELECT COUNT(*) FROM \"$table\";" 2>/dev/null | tr -d ' ' || echo "0")
        echo "• $table: $row_count rows"
    done

    echo
    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo "1. Run data processing pipeline:"
    echo "   ./scripts/run-data-pipeline.sh --full-refresh"
    echo
    echo "2. Validate data quality:"
    echo "   ./scripts/validate-data-quality.sh --verbose"
    echo
    echo "3. Test individual data kits:"
    echo "   ./scripts/test-datakit.sh bronze-pagila"
    echo
    echo -e "${YELLOW}💡 Database Access:${NC}"
    echo "Connect with: docker exec -it pagila-source psql -U postgres -d pagila"
    echo
}

# Parse command line arguments
FORCE_RELOAD=false
USE_INLINE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force-reload)
            FORCE_RELOAD=true
            shift
            ;;
        --use-inline)
            USE_INLINE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force-reload    Drop existing data and reload"
            echo "  --use-inline     Use minimal inline sample data instead of full Pagila"
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
    check_prerequisites

    # Check if database already has data
    local existing_tables=$(docker exec pagila-source psql -U postgres -d pagila -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ' || echo "0")

    if [ "$existing_tables" -gt 0 ] && [ "$FORCE_RELOAD" = false ]; then
        log_info "Database already contains $existing_tables tables"
        log_info "Use --force-reload to recreate the database"
        verify_data_integrity && show_database_info
        return 0
    fi

    if [ "$FORCE_RELOAD" = true ]; then
        log_warning "Force reloading database (existing data will be lost)..."
        docker exec pagila-source psql -U postgres -d pagila -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1 || true
    fi

    # Load sample data
    if [ "$USE_INLINE" = true ]; then
        log_info "Using minimal inline sample data..."
        create_inline_pagila_data
    else
        log_info "Attempting to download full Pagila sample database..."
        if ! download_pagila_files; then
            log_warning "Download failed, falling back to inline sample data..."
            create_inline_pagila_data
        fi
    fi

    load_pagila_database
    verify_data_integrity
    cleanup_temp_files
    show_database_info
}

# Handle script errors
trap 'log_error "Sample data loading failed at line $LINENO. Exit code: $?"; cleanup_temp_files' ERR

# Run main function
main "$@"
