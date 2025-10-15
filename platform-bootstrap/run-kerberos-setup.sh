#!/bin/bash
# Wrapper script to run Kerberos setup with output logging
# Shows output on screen AND saves to durable log file

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# Create timestamped log file and symlink to latest
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/kerberos-setup-$TIMESTAMP.log"
LATEST_LOG="$LOG_DIR/kerberos-setup-latest.log"

# Colors for terminal output only
if [ -t 1 ]; then
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    CYAN=''
    GREEN=''
    YELLOW=''
    NC=''
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Starting Kerberos Setup Wizard with Logging${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}✓${NC} Output will be displayed on screen"
echo -e "${GREEN}✓${NC} Complete log saved to: ${YELLOW}$LOG_FILE${NC}"
echo -e "${GREEN}✓${NC} Latest log symlink: ${YELLOW}$LATEST_LOG${NC}"
echo ""
echo -e "${CYAN}💡 Tip: If you encounter issues, copy the log file to ChatGPT/Claude for help${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Run the setup with tee to both display and log
# Use script command to preserve colors in log file
script -q -c "$SCRIPT_DIR/setup-kerberos.sh $*" "$LOG_FILE"
RESULT=$?

# Create symlink to latest log
ln -sf "$LOG_FILE" "$LATEST_LOG"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Setup completed successfully!${NC}"
else
    echo -e "${YELLOW}⚠️  Setup exited with code: $RESULT${NC}"
fi

echo ""
echo -e "${CYAN}Log files:${NC}"
echo "  • Full log: $LOG_FILE"
echo "  • Latest log: $LATEST_LOG"
echo ""

# If there were errors, offer to generate diagnostic context
if [ $RESULT -ne 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${YELLOW}Need help troubleshooting?${NC}"
    echo ""
    echo "1. Generate diagnostic context:"
    echo -e "   ${CYAN}./generate-diagnostic-context.sh${NC}"
    echo ""
    echo "2. Copy the generated report to ChatGPT or Claude"
    echo ""
    echo "3. Or copy the setup log:"
    echo -e "   ${CYAN}cat $LATEST_LOG | pbcopy${NC}  # macOS"
    echo -e "   ${CYAN}cat $LATEST_LOG | xclip${NC}   # Linux"
    echo ""
fi

exit $RESULT
