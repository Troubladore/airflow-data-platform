#!/bin/bash
# Wrapper script to run Kerberos setup with output logging
# Shows output on screen AND saves to durable log file

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
else
    # Fallback if library not found
    echo "Warning: formatting library not found, using basic output" >&2
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# Create timestamped log file and symlink to latest
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/kerberos-setup-$TIMESTAMP.log"
LATEST_LOG="$LOG_DIR/kerberos-setup-latest.log"

print_divider
print_msg "${CYAN}Starting Kerberos Setup Wizard with Logging${NC}"
print_divider
echo ""
print_check "PASS" "Output will be displayed on screen"
print_msg "${GREEN}✓${NC} Complete log saved to: ${YELLOW}$LOG_FILE${NC}"
print_msg "${GREEN}✓${NC} Latest log symlink: ${YELLOW}$LATEST_LOG${NC}"
echo ""
print_msg "${CYAN}💡 Tip: If you encounter issues, copy the log file to ChatGPT/Claude for help${NC}"
echo ""
print_divider
echo ""

# Run the setup with tee to both display and log
# Use script command to preserve colors in log file
script -q -c "$SCRIPT_DIR/setup-kerberos.sh $*" "$LOG_FILE"
RESULT=$?

# Create symlink to latest log
ln -sf "$LOG_FILE" "$LATEST_LOG"

echo ""
print_divider
echo ""

if [ $RESULT -eq 0 ]; then
    print_success "Setup completed successfully!"
else
    print_warning "Setup exited with code: $RESULT"
fi

echo ""
print_msg "${CYAN}Log files:${NC}"
print_bullet "Full log: $LOG_FILE"
print_bullet "Latest log: $LATEST_LOG"
echo ""

# If there were errors, offer to generate diagnostic context
if [ $RESULT -ne 0 ]; then
    print_divider
    echo ""
    print_warning "Need help troubleshooting?"
    echo ""
    echo "1. Generate diagnostic context:"
    print_msg "   ${CYAN}./diagnostics/generate-diagnostic-context.sh${NC}"
    echo ""
    echo "2. Copy the generated report to ChatGPT or Claude"
    echo ""
    echo "3. Or copy the setup log:"
    print_msg "   ${CYAN}cat $LATEST_LOG | pbcopy${NC}  # macOS"
    print_msg "   ${CYAN}cat $LATEST_LOG | xclip${NC}   # Linux"
    echo ""
fi

exit $RESULT
