#!/bin/bash
# Shell Script Syntax Validator
# =============================
# Validates shell scripts for common syntax errors that cause runtime failures
# Uses shellcheck and bash -n for comprehensive validation

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Find script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"

echo "================================"
echo "Shell Script Syntax Validation"
echo "================================"
echo ""

# Track results
TOTAL_SCRIPTS=0
PASSED_SCRIPTS=0
FAILED_SCRIPTS=0
WARNINGS=0

# List of critical scripts to validate
CRITICAL_SCRIPTS=(
    "clean-slate.sh"
    "setup-kerberos.sh"
    "diagnose-kerberos.sh"
    "krb5-auth-test.sh"
    "test-sql-direct.sh"
    "test-sql-simple.sh"
    "generate-diagnostic-context.sh"
    "run-kerberos-setup.sh"
)

echo "Validating critical scripts..."
echo ""

# Function to validate a script
validate_script() {
    local script="$1"
    local script_path="$PLATFORM_DIR/$script"

    TOTAL_SCRIPTS=$((TOTAL_SCRIPTS + 1))

    echo -n "Checking $script... "

    if [ ! -f "$script_path" ]; then
        echo -e "${YELLOW}SKIP${NC} (not found)"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    # First, check with bash -n (syntax check without execution)
    if ! bash -n "$script_path" 2>/dev/null; then
        echo -e "${RED}FAIL${NC} (syntax error)"
        echo "  Error details:"
        bash -n "$script_path" 2>&1 | sed 's/^/    /'
        FAILED_SCRIPTS=$((FAILED_SCRIPTS + 1))
        return
    fi

    # Check for common problematic patterns
    local issues_found=false
    local issue_details=""

    # Check for 'local' outside functions
    if grep -n '^[[:space:]]*local ' "$script_path" | grep -v '^[[:space:]]*#' >/dev/null 2>&1; then
        # Now check if these are actually outside functions
        # This is a simplified check - may have false positives
        local in_function=false
        local line_num=0
        while IFS= read -r line; do
            line_num=$((line_num + 1))

            # Check for function start
            if echo "$line" | grep -E '^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)\s*\{' >/dev/null 2>&1; then
                in_function=true
            elif echo "$line" | grep -E '^function\s+[a-zA-Z_][a-zA-Z0-9_]*' >/dev/null 2>&1; then
                in_function=true
            fi

            # Check for function end (simplified - counts braces)
            if [ "$in_function" = true ] && echo "$line" | grep -E '^\}' >/dev/null 2>&1; then
                in_function=false
            fi

            # Check for 'local' usage
            if [ "$in_function" = false ] && echo "$line" | grep -E '^[[:space:]]*local ' >/dev/null 2>&1; then
                if ! echo "$line" | grep -E '^[[:space:]]*#' >/dev/null 2>&1; then
                    issues_found=true
                    issue_details="${issue_details}    Line $line_num: 'local' used outside function\n"
                fi
            fi
        done < "$script_path"
    fi

    # Check for unclosed quotes (simplified check)
    if awk '
        BEGIN { sq=0; dq=0 }
        {
            # Count quotes, ignoring escaped ones
            gsub(/\\'\''/, "", $0)  # Remove escaped single quotes
            gsub(/\\"/, "", $0)      # Remove escaped double quotes
            gsub(/[^"]*"[^"]*"/, "", $0)  # Remove paired double quotes
            gsub(/[^'\'']*'\''[^'\'']*'\''/, "", $0)  # Remove paired single quotes

            # Count remaining quotes
            sq += gsub(/'\''/, "", $0)
            dq += gsub(/"/, "", $0)
        }
        END {
            if (sq % 2 != 0) exit 1
            if (dq % 2 != 0) exit 2
        }
    ' "$script_path" 2>/dev/null; then
        : # Quotes are balanced
    else
        issues_found=true
        issue_details="${issue_details}    Warning: Possible unbalanced quotes\n"
    fi

    # Check for missing 'fi', 'done', 'esac'
    local if_count=$(grep -c '^\s*if\s\|^\s*elif\s' "$script_path" 2>/dev/null || echo 0)
    local fi_count=$(grep -c '^\s*fi\s*$\|^\s*fi\s*#' "$script_path" 2>/dev/null || echo 0)
    if [ $if_count -ne $fi_count ]; then
        issues_found=true
        issue_details="${issue_details}    Warning: if/fi mismatch (if: $if_count, fi: $fi_count)\n"
    fi

    if [ "$issues_found" = true ]; then
        echo -e "${YELLOW}WARN${NC}"
        echo -e "$issue_details"
        WARNINGS=$((WARNINGS + 1))
        PASSED_SCRIPTS=$((PASSED_SCRIPTS + 1))
    else
        echo -e "${GREEN}PASS${NC}"
        PASSED_SCRIPTS=$((PASSED_SCRIPTS + 1))
    fi
}

# Validate each critical script
for script in "${CRITICAL_SCRIPTS[@]}"; do
    validate_script "$script"
done

echo ""
echo "================================"
echo "Additional Checks"
echo "================================"
echo ""

# Check if shellcheck is available for deeper analysis
if command -v shellcheck >/dev/null 2>&1; then
    echo "Running ShellCheck for deeper analysis..."
    echo ""

    for script in "${CRITICAL_SCRIPTS[@]}"; do
        script_path="$PLATFORM_DIR/$script"
        if [ -f "$script_path" ]; then
            echo "ShellCheck: $script"
            # Run shellcheck with common exclusions for style issues
            # SC2086: Double quote to prevent globbing
            # SC2181: Check exit code directly
            if shellcheck -x -e SC2086,SC2181 "$script_path" 2>&1 | grep -E 'error|warning'; then
                echo ""
            else
                echo "  No issues found"
            fi
        fi
    done
else
    echo -e "${YELLOW}ShellCheck not installed${NC}"
    echo "Install with: apt-get install shellcheck"
    echo "For comprehensive shell script analysis"
fi

echo ""
echo "================================"
echo "Execution Tests"
echo "================================"
echo ""

echo "Testing that scripts can execute without immediate syntax errors..."
echo "(Running with --help or bash -n to verify basic functionality)"
echo ""

# Test critical scripts can at least show help or pass syntax check
for script in "${CRITICAL_SCRIPTS[@]}"; do
    script_path="$PLATFORM_DIR/$script"

    if [ ! -f "$script_path" ]; then
        continue
    fi

    echo -n "Execution test: $script... "

    # Different scripts need different test approaches
    case "$script" in
        krb5-auth-test.sh)
            # This script supports --help
            if "$script_path" --help >/dev/null 2>&1; then
                echo -e "${GREEN}PASS${NC} (--help works)"
            else
                echo -e "${RED}FAIL${NC} (cannot run --help)"
                FAILED_SCRIPTS=$((FAILED_SCRIPTS + 1))
            fi
            ;;
        *)
            # Just verify syntax for other scripts
            if bash -n "$script_path" 2>/dev/null; then
                echo -e "${GREEN}PASS${NC} (syntax OK)"
            else
                echo -e "${RED}FAIL${NC} (syntax error prevents execution)"
                FAILED_SCRIPTS=$((FAILED_SCRIPTS + 1))
            fi
            ;;
    esac
done

echo ""
echo "================================"
echo "Summary"
echo "================================"
echo ""
echo "Total scripts checked: $TOTAL_SCRIPTS"
echo -e "Passed: ${GREEN}$PASSED_SCRIPTS${NC}"
echo -e "Failed: ${RED}$FAILED_SCRIPTS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [ $FAILED_SCRIPTS -gt 0 ]; then
    echo -e "${RED}❌ VALIDATION FAILED${NC}"
    echo "Fix syntax errors before committing!"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠ VALIDATION PASSED WITH WARNINGS${NC}"
    echo "Review warnings to prevent runtime issues"
    exit 0
else
    echo -e "${GREEN}✅ ALL VALIDATIONS PASSED${NC}"
    exit 0
fi
