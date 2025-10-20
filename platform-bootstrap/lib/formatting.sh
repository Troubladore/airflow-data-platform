#!/bin/bash
# Shared Formatting Library for Platform Scripts
# ===============================================
# Provides consistent terminal output formatting across all scripts
# Handles color codes, Unicode characters, and NO_COLOR standard
#
# Usage:
#   source "$(dirname "$0")/lib/formatting.sh"
#   print_header "My Section"
#   print_check "PASS" "All tests passed"

# Detect terminal and color support
_init_formatting() {
    # Check if output is to a terminal AND NO_COLOR is not set
    if [ -t 1 ] && [ -z "${NO_COLOR}" ]; then
        # Full color and Unicode support
        export USE_COLOR=true
        export USE_UNICODE=true

        # Color codes
        export GREEN='\033[0;32m'
        export RED='\033[0;31m'
        export YELLOW='\033[1;33m'
        export CYAN='\033[0;36m'
        export BLUE='\033[0;34m'
        export MAGENTA='\033[0;35m'
        export BOLD='\033[1m'
        export NC='\033[0m' # No Color

        # Unicode symbols
        export CHECK_MARK="✓"
        export CROSS_MARK="✗"
        export WARNING_SIGN="⚠"
        export INFO_SIGN="ℹ"
        export ARROW="▶"
        export BOX_HORIZONTAL="─"
        export BOX_DOUBLE="═"
        export CIRCLE="○"
    else
        # Plain ASCII output
        export USE_COLOR=false
        export USE_UNICODE=false

        # Empty color codes
        export GREEN=''
        export RED=''
        export YELLOW=''
        export CYAN=''
        export BLUE=''
        export MAGENTA=''
        export BOLD=''
        export NC=''

        # ASCII alternatives
        export CHECK_MARK="[OK]"
        export CROSS_MARK="[FAIL]"
        export WARNING_SIGN="[WARN]"
        export INFO_SIGN="[INFO]"
        export ARROW=">"
        export BOX_HORIZONTAL="-"
        export BOX_DOUBLE="="
        export CIRCLE="o"
    fi
}

# Initialize formatting on source
_init_formatting

# Print colored or plain message
# Usage: print_msg "message" [no_newline]
print_msg() {
    local message="$1"
    local no_newline="$2"

    if [ "$USE_COLOR" = true ]; then
        if [ "$no_newline" = "no_newline" ]; then
            echo -en "$message"
        else
            echo -e "$message"
        fi
    else
        # Strip any color codes that might have been included
        message=$(echo "$message" | sed 's/\x1b\[[0-9;]*m//g')
        if [ "$no_newline" = "no_newline" ]; then
            echo -n "$message"
        else
            echo "$message"
        fi
    fi
}

# Print a header section
# Usage: print_header "Section Title"
print_header() {
    local title="$1"
    echo ""
    if [ "$USE_UNICODE" = true ]; then
        print_msg "${BOLD}${CYAN}$(printf '%.0s═' {1..56})${NC}"
        print_msg "${BOLD}${CYAN}  $title${NC}"
        print_msg "${BOLD}${CYAN}$(printf '%.0s═' {1..56})${NC}"
    else
        echo "========================================================"
        echo "  $title"
        echo "========================================================"
    fi
    echo ""
}

# Print a section divider
# Usage: print_section "Section Name"
print_section() {
    local title="$1"
    echo ""
    if [ "$USE_UNICODE" = true ]; then
        print_msg "${BOLD}${BLUE}${ARROW} $title${NC}"
        print_msg "${BLUE}$(printf '%.0s─' {1..50})${NC}"
    else
        echo "> $title"
        echo "--------------------------------------------------"
    fi
}

# Print a status check
# Usage: print_check "PASS|FAIL|WARN|INFO" "message" ["detail"]
print_check() {
    local status="$1"
    local message="$2"
    local detail="$3"

    case "$status" in
        "PASS")
            if [ "$USE_UNICODE" = true ]; then
                print_msg "  ${GREEN}${CHECK_MARK}${NC} ${message}"
            else
                echo "  [PASS] ${message}"
            fi
            ;;
        "FAIL")
            if [ "$USE_UNICODE" = true ]; then
                print_msg "  ${RED}${CROSS_MARK}${NC} ${message}"
            else
                echo "  [FAIL] ${message}"
            fi
            ;;
        "WARN")
            if [ "$USE_UNICODE" = true ]; then
                print_msg "  ${YELLOW}${WARNING_SIGN}${NC} ${message}"
            else
                echo "  [WARN] ${message}"
            fi
            ;;
        "INFO")
            if [ "$USE_UNICODE" = true ]; then
                print_msg "  ${CYAN}${INFO_SIGN}${NC} ${message}"
            else
                echo "  [INFO] ${message}"
            fi
            ;;
        *)
            echo "  ${message}"
            ;;
    esac

    if [ -n "$detail" ]; then
        if [ "$USE_COLOR" = true ]; then
            print_msg "    ${CYAN}${detail}${NC}"
        else
            echo "    ${detail}"
        fi
    fi
}

# Print an error message
# Usage: print_error "error message"
print_error() {
    local message="$1"
    if [ "$USE_COLOR" = true ]; then
        print_msg "${RED}Error: ${message}${NC}" >&2
    else
        echo "Error: ${message}" >&2
    fi
}

# Print a warning message
# Usage: print_warning "warning message"
print_warning() {
    local message="$1"
    if [ "$USE_COLOR" = true ]; then
        print_msg "${YELLOW}Warning: ${message}${NC}"
    else
        echo "Warning: ${message}"
    fi
}

# Print an info message
# Usage: print_info "info message"
print_info() {
    local message="$1"
    if [ "$USE_COLOR" = true ]; then
        print_msg "${CYAN}${INFO_SIGN} ${message}${NC}"
    else
        echo "${INFO_SIGN} ${message}"
    fi
}

# Print a success message
# Usage: print_success "success message"
print_success() {
    local message="$1"
    if [ "$USE_COLOR" = true ]; then
        print_msg "${GREEN}${message}${NC}"
    else
        echo "${message}"
    fi
}

# Print step indicator (for multi-step processes)
# Usage: print_step "1" "Step description"
print_step() {
    local step_num="$1"
    local description="$2"

    if [ "$USE_COLOR" = true ]; then
        print_msg "${BOLD}Step ${step_num}:${NC} ${description}"
    else
        echo "Step ${step_num}: ${description}"
    fi
}

# Get formatted checkmark for inline use
# Usage: echo "Status: $(get_checkmark)"
get_checkmark() {
    echo "${CHECK_MARK}"
}

# Get formatted cross mark for inline use
# Usage: echo "Status: $(get_crossmark)"
get_crossmark() {
    echo "${CROSS_MARK}"
}

# Check if colors are enabled
# Usage: if is_color_enabled; then ... fi
is_color_enabled() {
    [ "$USE_COLOR" = true ]
}

# Check if Unicode is enabled
# Usage: if is_unicode_enabled; then ... fi
is_unicode_enabled() {
    [ "$USE_UNICODE" = true ]
}

# Format a status line with color
# Usage: format_status "PASS" "Test completed"
format_status() {
    local status="$1"
    local message="$2"

    case "$status" in
        "PASS")
            if [ "$USE_COLOR" = true ]; then
                echo -e "${GREEN}${message}${NC}"
            else
                echo "[PASS] ${message}"
            fi
            ;;
        "FAIL")
            if [ "$USE_COLOR" = true ]; then
                echo -e "${RED}${message}${NC}"
            else
                echo "[FAIL] ${message}"
            fi
            ;;
        "WARN")
            if [ "$USE_COLOR" = true ]; then
                echo -e "${YELLOW}${message}${NC}"
            else
                echo "[WARN] ${message}"
            fi
            ;;
        *)
            echo "${message}"
            ;;
    esac
}

# Print a simple divider line
# Usage: print_divider [length]
print_divider() {
    local length="${1:-50}"
    if [ "$USE_UNICODE" = true ]; then
        print_msg "${BLUE}$(printf "%.0s${BOX_HORIZONTAL}" $(seq 1 $length))${NC}"
    else
        printf "%.0s-" $(seq 1 $length)
        echo
    fi
}

# Print a bullet point item
# Usage: print_bullet "Item text"
print_bullet() {
    local text="$1"
    if [ "$USE_UNICODE" = true ]; then
        echo "  • ${text}"
    else
        echo "  * ${text}"
    fi
}

# Print an arrow item
# Usage: print_arrow "WARN|INFO|PASS|FAIL" "Item text"
print_arrow() {
    local status="$1"
    local text="$2"

    case "$status" in
        "PASS")
            print_msg "  ${GREEN}${ARROW}${NC} ${text}"
            ;;
        "FAIL")
            print_msg "  ${RED}${ARROW}${NC} ${text}"
            ;;
        "WARN")
            print_msg "  ${YELLOW}${ARROW}${NC} ${text}"
            ;;
        "INFO")
            print_msg "  ${CYAN}${ARROW}${NC} ${text}"
            ;;
        *)
            print_msg "  ${ARROW} ${text}"
            ;;
    esac
}

# Print a list header
# Usage: print_list_header "Header text"
print_list_header() {
    local text="$1"
    print_msg "${YELLOW}${text}${NC}"
}

# Print an environment variable status
# Usage: print_env_var "VAR_NAME" "$VAR_VALUE"
print_env_var() {
    local var_name="$1"
    local var_value="$2"

    if [ -n "$var_value" ]; then
        print_msg "    ${GREEN}${CHECK_MARK}${NC} ${var_name}=${var_value}"
    else
        print_msg "    ${CYAN}${CIRCLE}${NC} ${var_name} (not set)"
    fi
}

# Print a title with optional emoji
# Usage: print_title "Title text" "🧹"  (emoji is optional)
print_title() {
    local title="$1"
    local emoji="$2"

    if [ "$USE_UNICODE" = true ] && [ -n "$emoji" ]; then
        echo "${emoji} ${title}"
    else
        echo "${title}"
    fi
}

# Print a status message with checkmark/cross
# Usage: print_status "PASS|FAIL|WARN" "message"
print_status() {
    local status="$1"
    local message="$2"

    case "$status" in
        "PASS")
            print_msg "${GREEN}${CHECK_MARK}${NC} ${message}"
            ;;
        "FAIL")
            print_msg "${RED}${CROSS_MARK}${NC} ${message}"
            ;;
        "WARN")
            print_msg "${YELLOW}${WARNING_SIGN}${NC} ${message}"
            ;;
        "INFO")
            print_msg "${CYAN}${INFO_SIGN}${NC} ${message}"
            ;;
        *)
            echo "${message}"
            ;;
    esac
}

# Export functions for use by sourcing scripts
export -f print_msg
export -f print_header
export -f print_section
export -f print_check
export -f print_error
export -f print_warning
export -f print_info
export -f print_success
export -f print_step
export -f get_checkmark
export -f get_crossmark
export -f is_color_enabled
export -f is_unicode_enabled
export -f format_status
export -f print_divider
export -f print_bullet
export -f print_arrow
export -f print_list_header
export -f print_env_var
export -f print_title
export -f print_status