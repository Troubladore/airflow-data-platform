#!/bin/bash
# Comprehensive Kerberos diagnostic tool for WSL2/Docker integration
# Helps identify and fix common Kerberos ticket sharing issues

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🔍 Kerberos Diagnostic Tool for Docker Integration"
echo "=================================================="
echo ""

# Try to detect Windows domain and username if in WSL2
WINDOWS_DOMAIN=""
WINDOWS_USERNAME=""
if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
    # We're in WSL2, try to get Windows domain and username
    if command -v powershell.exe >/dev/null 2>&1; then
        WINDOWS_DOMAIN=$(powershell.exe -Command "([System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()).Name" 2>/dev/null | tr -d '\r' | tr '[:lower:]' '[:upper:]')
        if [ -n "$WINDOWS_DOMAIN" ] && [[ "$WINDOWS_DOMAIN" != *"Exception"* ]]; then
            echo -e "${GREEN}✓ Detected Windows domain: $WINDOWS_DOMAIN${NC}"
        fi

        WINDOWS_USERNAME=$(powershell.exe -Command "\$env:USERNAME" 2>/dev/null | tr -d '\r')
        if [ -n "$WINDOWS_USERNAME" ]; then
            echo -e "${GREEN}✓ Detected Windows username: $WINDOWS_USERNAME${NC}"
        fi
    fi
fi

# Function to check a condition and report
check_condition() {
    local description="$1"
    local command="$2"
    local expected="$3"

    echo -n "Checking: $description... "
    if eval "$command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

# 1. Check host Kerberos tickets
echo -e "\n${BLUE}=== 1. HOST KERBEROS TICKETS ===${NC}"

if command -v klist >/dev/null 2>&1; then
    echo -e "${GREEN}✓ klist command found${NC}"

    # Run klist and capture output
    if klist 2>/dev/null | grep -q "Default principal"; then
        echo -e "${GREEN}✓ Kerberos tickets found!${NC}"
        echo ""
        echo "Ticket details:"
        klist | head -5

        # Extract company domain from principal
        PRINCIPAL=$(klist 2>/dev/null | grep "Default principal:" | sed 's/Default principal: //')
        DETECTED_DOMAIN=""
        if [ -n "$PRINCIPAL" ]; then
            # Extract domain from principal (e.g., user@COMPANY.COM -> COMPANY.COM)
            DETECTED_DOMAIN=$(echo "$PRINCIPAL" | sed 's/.*@//')
        fi

        # Extract ticket cache location
        TICKET_CACHE=$(klist 2>/dev/null | grep "Ticket cache:" | sed 's/Ticket cache: //')
        echo ""
        echo -e "${YELLOW}📍 Ticket cache location: $TICKET_CACHE${NC}"

        # Parse different ticket cache formats and store values
        DETECTED_CACHE_TYPE=""
        DETECTED_CACHE_PATH=""
        DETECTED_CACHE_TICKET=""

        if [[ "$TICKET_CACHE" == FILE:* ]]; then
            CACHE_FILE=${TICKET_CACHE#FILE:}
            echo "  Type: FILE"
            echo "  Path: $CACHE_FILE"
            if [ -f "$CACHE_FILE" ]; then
                echo -e "  ${GREEN}✓ File exists${NC}"
                ls -la "$CACHE_FILE"

                # Determine .env values
                DETECTED_CACHE_TYPE="FILE"
                DETECTED_CACHE_PATH=$(dirname "$CACHE_FILE")
                DETECTED_CACHE_TICKET=$(basename "$CACHE_FILE")
            else
                echo -e "  ${RED}✗ File does not exist${NC}"
            fi
        elif [[ "$TICKET_CACHE" == DIR::* ]]; then
            CACHE_DIR=${TICKET_CACHE#DIR::}
            echo "  Type: DIR (collection)"
            echo "  Path: $CACHE_DIR"
            if [ -d "$CACHE_DIR" ]; then
                echo -e "  ${GREEN}✓ Directory exists${NC}"
                echo "  Contents:"
                ls -la "$CACHE_DIR" 2>/dev/null | head -5

                # Find the actual ticket file in the directory
                # Check both root level and subdirectories
                TICKET_FOUND=""

                # First check subdirectories (like dev/)
                for subdir in "$CACHE_DIR"/*; do
                    if [ -d "$subdir" ]; then
                        for ticket_file in "$subdir"/*; do
                            if [ -f "$ticket_file" ] && [[ "$(basename "$ticket_file")" != "primary" ]]; then
                                # Found ticket in subdirectory
                                DETECTED_CACHE_TYPE="DIR"
                                DETECTED_CACHE_PATH="$CACHE_DIR"
                                # Get relative path from cache dir
                                SUBDIR_NAME=$(basename "$subdir")
                                TICKET_NAME=$(basename "$ticket_file")
                                DETECTED_CACHE_TICKET="$SUBDIR_NAME/$TICKET_NAME"
                                TICKET_FOUND="yes"
                                echo -e "  ${GREEN}✓ Found ticket: $DETECTED_CACHE_TICKET${NC}"
                                break 2
                            fi
                        done
                    fi
                done

                # If not found in subdirs, check root level
                if [ -z "$TICKET_FOUND" ]; then
                    for ticket_file in "$CACHE_DIR"/*; do
                        if [ -f "$ticket_file" ] && [[ "$(basename "$ticket_file")" != "primary" ]]; then
                            DETECTED_CACHE_TYPE="DIR"
                            DETECTED_CACHE_PATH="$CACHE_DIR"
                            DETECTED_CACHE_TICKET=$(basename "$ticket_file")
                            echo -e "  ${GREEN}✓ Found ticket: $DETECTED_CACHE_TICKET${NC}"
                            break
                        fi
                    done
                fi
            else
                echo -e "  ${RED}✗ Directory does not exist${NC}"
            fi
        elif [[ "$TICKET_CACHE" == KCM:* ]]; then
            echo "  Type: KCM (Kernel Credential Cache)"
            echo -e "  ${YELLOW}⚠️  KCM tickets need special handling for Docker${NC}"
        else
            # Assume it's a simple file path
            echo "  Type: FILE (assumed)"
            if [ -f "$TICKET_CACHE" ]; then
                echo -e "  ${GREEN}✓ File exists at: $TICKET_CACHE${NC}"

                # Determine .env values
                DETECTED_CACHE_TYPE="FILE"
                DETECTED_CACHE_PATH=$(dirname "$TICKET_CACHE")
                DETECTED_CACHE_TICKET=$(basename "$TICKET_CACHE")
            else
                echo -e "  ${RED}✗ File not found at: $TICKET_CACHE${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ No Kerberos tickets found${NC}"
        # Use detected values for the kinit command
        if [ -n "$WINDOWS_USERNAME" ] && [ -n "$WINDOWS_DOMAIN" ]; then
            echo "  Run: kinit ${WINDOWS_USERNAME}@${WINDOWS_DOMAIN}"
        elif [ -n "$WINDOWS_DOMAIN" ]; then
            echo "  Run: kinit YOUR_USERNAME@${WINDOWS_DOMAIN}"
        else
            echo "  Run: kinit YOUR_USERNAME@DOMAIN.COM"
        fi
    fi
else
    echo -e "${RED}✗ klist command not found${NC}"
    echo "  Install with: sudo apt-get install krb5-user"
fi

# 2. Check expected ticket locations
echo -e "\n${BLUE}=== 2. COMMON TICKET LOCATIONS ===${NC}"

TICKET_LOCATIONS=(
    "/tmp/krb5cc_$(id -u)"
    "$HOME/.krb5_cache/krb5cc"
    "$HOME/.krb5-cache/dev/tkt"
    "/tmp/krb5cc_*"
)

FOUND_TICKETS=""
for location in "${TICKET_LOCATIONS[@]}"; do
    # Use ls to handle wildcards
    for file in $location; do
        if [ -e "$file" ]; then
            echo -e "${GREEN}✓ Found ticket at: $file${NC}"
            if [ -f "$file" ]; then
                echo "    Size: $(stat -c%s "$file") bytes"
                echo "    Modified: $(stat -c%y "$file" | cut -d' ' -f1,2)"
            elif [ -d "$file" ]; then
                echo "    Type: Directory (ticket collection)"
                echo "    Contents: $(ls -1 "$file" 2>/dev/null | wc -l) files"
            fi
            FOUND_TICKETS="$FOUND_TICKETS $file"
        fi
    done
done

if [ -z "$FOUND_TICKETS" ]; then
    echo -e "${RED}✗ No tickets found in common locations${NC}"
fi

# 3. Check Docker setup
echo -e "\n${BLUE}=== 3. DOCKER ENVIRONMENT ===${NC}"

if docker info >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Docker is running${NC}"

    # Check for platform network
    if docker network ls | grep -q "platform_network"; then
        echo -e "${GREEN}✓ platform_network exists${NC}"
    else
        echo -e "${RED}✗ platform_network does not exist${NC}"
        echo "  Run: docker network create platform_network"
    fi

    # Check for Kerberos cache volume
    if docker volume ls | grep -q "platform_kerberos_cache"; then
        echo -e "${GREEN}✓ platform_kerberos_cache volume exists${NC}"

        # Check volume contents
        echo "  Checking volume contents..."
        docker run --rm -v platform_kerberos_cache:/check:ro alpine ls -la /check/ 2>/dev/null || echo "    (empty)"
    else
        echo -e "${RED}✗ platform_kerberos_cache volume does not exist${NC}"
        echo "  Run: docker volume create platform_kerberos_cache"
    fi

    # Check if kerberos service is running
    if docker ps --format "table {{.Names}}" | grep -q "kerberos-platform-service"; then
        echo -e "${GREEN}✓ kerberos-platform-service is running${NC}"

        # Check service logs
        echo "  Recent logs:"
        docker logs kerberos-platform-service --tail 3 2>&1 | sed 's/^/    /'
    else
        echo -e "${YELLOW}⚠️  kerberos-platform-service is not running${NC}"
        echo "  Run: make platform-start"
    fi
else
    echo -e "${RED}✗ Docker is not running or not accessible${NC}"
fi

# 3.5. Check Sidecar Health Status
echo -e "\n${BLUE}=== 3.5. SIDECAR HEALTH STATUS ===${NC}"

if docker ps --format "table {{.Names}}" | grep -q "kerberos-platform-service" 2>/dev/null; then
    echo "Querying health status from running sidecar..."
    echo ""

    # Get health check output
    HEALTH_OUTPUT=$(docker exec kerberos-platform-service /scripts/health-check.sh 2>/dev/null || echo '{"status":"error","message":"Health check script failed"}')

    # Parse JSON output
    STATUS=$(echo "$HEALTH_OUTPUT" | grep -o '"status": *"[^"]*"' | cut -d'"' -f4)
    MESSAGE=$(echo "$HEALTH_OUTPUT" | grep -o '"message": *"[^"]*"' | cut -d'"' -f4)
    ERROR_TYPE=$(echo "$HEALTH_OUTPUT" | grep -o '"error_type": *"[^"]*"' | cut -d'"' -f4)
    FIX_GUIDANCE=$(echo "$HEALTH_OUTPUT" | grep -o '"fix_guidance": *"[^"]*"' | sed 's/"fix_guidance": *"//; s/"$//')
    EXPIRY=$(echo "$HEALTH_OUTPUT" | grep -o '"ticket_expiry": *"[^"]*"' | cut -d'"' -f4)

    if [ "$STATUS" == "healthy" ]; then
        echo -e "${GREEN}✓ Sidecar is HEALTHY${NC}"
        echo "  Status: $MESSAGE"
        if [ -n "$EXPIRY" ]; then
            echo "  Ticket expires: $EXPIRY"
        fi
        echo ""
        echo -e "${GREEN}Everything looks good! Your Kerberos sidecar is working.${NC}"
    elif [ "$STATUS" == "unhealthy" ]; then
        echo -e "${RED}✗ Sidecar is UNHEALTHY${NC}"
        echo "  Problem: $MESSAGE"
        if [ -n "$ERROR_TYPE" ]; then
            echo "  Error Type: $ERROR_TYPE"
        fi
        echo ""

        if [ -n "$FIX_GUIDANCE" ]; then
            echo -e "${YELLOW}HOW TO FIX:${NC}"
            echo "$FIX_GUIDANCE" | sed 's/\\n/\n/g' | sed 's/^/  /'
        fi

        echo ""
        echo "Recent sidecar logs:"
        docker logs kerberos-platform-service --tail 10 2>&1 | sed 's/^/  /'

        echo ""
        echo -e "${BLUE}Troubleshooting steps:${NC}"
        case "$ERROR_TYPE" in
            missing_password)
                echo "1. Set KRB_PASSWORD in your .env file"
                echo "2. Restart: make platform-restart"
                ;;
            missing_keytab)
                echo "1. Obtain keytab file from your DBA/Domain Admin"
                echo "2. Mount it in docker-compose.yml"
                echo "3. Restart: make platform-restart"
                ;;
            missing_principal)
                echo "1. Set KRB_PRINCIPAL in your .env file (example: user@DOMAIN.COM)"
                echo "2. Restart: make platform-restart"
                ;;
            password_auth_failed|keytab_auth_failed)
                echo "1. Check the error logs above for specific details"
                echo "2. Verify your credentials/keytab are correct"
                echo "3. Test manually: kinit your_principal"
                echo "4. Contact IT/Domain Admin if still failing"
                ;;
            ticket_manager_not_running)
                echo "1. Check if container crashed: docker ps -a"
                echo "2. View full logs: docker logs kerberos-platform-service"
                echo "3. Restart: make platform-restart"
                ;;
            *)
                echo "1. Check full logs: docker logs kerberos-platform-service"
                echo "2. Run diagnostic: ./diagnose-kerberos.sh"
                echo "3. Restart service: make platform-restart"
                ;;
        esac
    else
        echo -e "${YELLOW}⚠️  Could not determine health status${NC}"
        echo "  Response: $HEALTH_OUTPUT"
        echo ""
        echo "Check container logs:"
        docker logs kerberos-platform-service --tail 10 2>&1 | sed 's/^/  /'
    fi
else
    echo -e "${YELLOW}⚠️  kerberos-platform-service is not running${NC}"
    echo "Cannot check health status - service needs to be started"
    echo ""
    echo "Start with: make platform-start"
fi

# 4. Test ticket sharing
echo -e "\n${BLUE}=== 4. TICKET SHARING TEST ===${NC}"

if docker info >/dev/null 2>&1; then
    echo "Testing ticket visibility in container..."

    docker run --rm \
        --network platform_network \
        -v platform_kerberos_cache:/krb5/cache:ro \
        alpine sh -c '
            echo "  Checking /krb5/cache directory:"
            if [ -d /krb5/cache ]; then
                echo "    ✓ Directory exists"
                echo "    Contents:"
                ls -la /krb5/cache/ | sed "s/^/      /"
                if [ -f /krb5/cache/krb5cc ]; then
                    echo "    ✓ krb5cc file found"
                    echo "      Size: $(stat -c%s /krb5/cache/krb5cc) bytes"
                else
                    echo "    ✗ krb5cc file not found"
                fi
            else
                echo "    ✗ Directory does not exist"
            fi
        '
else
    echo -e "${RED}Cannot test - Docker not available${NC}"
fi

# 5. .env Configuration Values
echo -e "\n${BLUE}=== 5. EXACT .ENV CONFIGURATION ===${NC}"

if [ -n "$DETECTED_CACHE_TYPE" ] && [ -n "$DETECTED_CACHE_PATH" ] && [ -n "$DETECTED_CACHE_TICKET" ]; then
    echo -e "${GREEN}✅ Copy these exact values to your .env file:${NC}"
    echo ""
    echo "----------------------------------------"
    echo "# Add to platform-bootstrap/.env"

    # Include company domain if detected
    if [ -n "$DETECTED_DOMAIN" ]; then
        echo "COMPANY_DOMAIN=$DETECTED_DOMAIN"
    elif [ -n "$WINDOWS_DOMAIN" ]; then
        echo "COMPANY_DOMAIN=$WINDOWS_DOMAIN"
    else
        echo "COMPANY_DOMAIN=COMPANY.COM  # Replace with your actual domain"
    fi

    echo "KERBEROS_CACHE_TYPE=$DETECTED_CACHE_TYPE"

    # Handle home directory path for better portability
    if [[ "$DETECTED_CACHE_PATH" == "$HOME"* ]]; then
        RELATIVE_PATH=${DETECTED_CACHE_PATH#$HOME}
        echo "KERBEROS_CACHE_PATH=\${HOME}$RELATIVE_PATH"
    else
        echo "KERBEROS_CACHE_PATH=$DETECTED_CACHE_PATH"
    fi

    echo "KERBEROS_CACHE_TICKET=$DETECTED_CACHE_TICKET"
    echo "----------------------------------------"
    echo ""
    echo -e "${YELLOW}📝 Quick setup:${NC}"
    echo "1. Copy the configuration above"
    echo "2. Run: cd platform-bootstrap"
    echo "3. Run: cp .env.example .env  (if .env doesn't exist)"
    echo "4. Edit .env and replace the KERBEROS_* values with the ones above"
    echo "5. Run: make platform-start"
    echo ""
    echo -e "${BLUE}Or use automatic setup:${NC}"
    echo ""
    echo "Run this command to automatically update your .env:"
    echo ""

    # Generate the sed commands for automatic update
    if [[ "$DETECTED_CACHE_PATH" == "$HOME"* ]]; then
        RELATIVE_PATH=${DETECTED_CACHE_PATH#$HOME}
        PATH_VALUE="\${HOME}$RELATIVE_PATH"
    else
        PATH_VALUE="$DETECTED_CACHE_PATH"
    fi

    echo "cat << 'EOF' > /tmp/update_env.sh"
    echo "#!/bin/bash"
    echo "cd platform-bootstrap"
    echo "[ ! -f .env ] && cp .env.example .env"
    if [ -n "$DETECTED_DOMAIN" ]; then
        echo "sed -i 's/^COMPANY_DOMAIN=.*/COMPANY_DOMAIN=$DETECTED_DOMAIN/' .env"
    fi
    echo "sed -i 's/^KERBEROS_CACHE_TYPE=.*/KERBEROS_CACHE_TYPE=$DETECTED_CACHE_TYPE/' .env"
    echo "sed -i 's|^KERBEROS_CACHE_PATH=.*|KERBEROS_CACHE_PATH=$PATH_VALUE|' .env"
    echo "sed -i 's|^KERBEROS_CACHE_TICKET=.*|KERBEROS_CACHE_TICKET=$DETECTED_CACHE_TICKET|' .env"
    echo "echo '✅ .env file updated with Kerberos configuration!'"
    echo "EOF"
    echo "bash /tmp/update_env.sh"
elif [ -n "$TICKET_CACHE" ]; then
    if [[ "$TICKET_CACHE" == KCM:* ]]; then
        echo -e "${RED}❌ KCM ticket format detected${NC}"
        echo ""
        echo "KCM (Kernel Credential Cache) tickets cannot be easily shared with Docker."
        echo "You need to switch to FILE-based tickets:"
        echo ""
        echo "1. Set environment variable:"
        echo "   export KRB5CCNAME=FILE:/tmp/krb5cc_\$(id -u)"
        echo ""
        echo "2. Get a new ticket:"
        if [ -n "$WINDOWS_USERNAME" ] && [ -n "$WINDOWS_DOMAIN" ]; then
            echo "   kinit ${WINDOWS_USERNAME}@${WINDOWS_DOMAIN}"
        elif [ -n "$WINDOWS_DOMAIN" ]; then
            echo "   kinit YOUR_USERNAME@${WINDOWS_DOMAIN}"
        else
            echo "   kinit YOUR_USERNAME@DOMAIN.COM"
        fi
        echo ""
        echo "3. Run this diagnostic again to get .env values"
    else
        echo -e "${YELLOW}⚠️  Ticket location detected but no active ticket files found${NC}"
        echo ""

        # Try to provide better guidance based on what we know
        if [[ "$TICKET_CACHE" == DIR::* ]]; then
            CACHE_DIR=${TICKET_CACHE#DIR::}
            echo "Detected DIR format at: $CACHE_DIR"
            echo ""
            echo -e "${GREEN}Suggested .env configuration:${NC}"
            echo "----------------------------------------"
            echo "# Add to platform-bootstrap/.env"
            if [ -n "$DETECTED_DOMAIN" ]; then
                echo "COMPANY_DOMAIN=$DETECTED_DOMAIN"
            elif [ -n "$WINDOWS_DOMAIN" ]; then
                echo "COMPANY_DOMAIN=$WINDOWS_DOMAIN"
            else
                echo "COMPANY_DOMAIN=COMPANY.COM  # Replace with your actual domain"
            fi
            echo "KERBEROS_CACHE_TYPE=DIR"

            # Handle home directory path
            if [[ "$CACHE_DIR" == "$HOME"* ]]; then
                RELATIVE_PATH=${CACHE_DIR#$HOME}
                echo "KERBEROS_CACHE_PATH=\${HOME}$RELATIVE_PATH"
            else
                echo "KERBEROS_CACHE_PATH=$CACHE_DIR"
            fi

            # Guess common ticket patterns
            if [[ "$CACHE_DIR" == *"/.krb5-cache"* ]]; then
                echo "KERBEROS_CACHE_TICKET=dev/tkt  # Common pattern - adjust if different"
            else
                echo "KERBEROS_CACHE_TICKET=tkt  # Update based on actual ticket name"
            fi
            echo "----------------------------------------"
            echo ""
            echo "After updating .env, get a fresh ticket:"
            # Use detected values for kinit suggestion
            if [ -n "$WINDOWS_USERNAME" ] && [ -n "${DETECTED_DOMAIN:-$WINDOWS_DOMAIN}" ]; then
                echo "  kinit ${WINDOWS_USERNAME}@${DETECTED_DOMAIN:-$WINDOWS_DOMAIN}"
            elif [ -n "${DETECTED_DOMAIN:-$WINDOWS_DOMAIN}" ]; then
                echo "  kinit YOUR_USERNAME@${DETECTED_DOMAIN:-$WINDOWS_DOMAIN}"
            else
                echo "  kinit YOUR_USERNAME@DOMAIN.COM"
            fi
        elif [[ "$TICKET_CACHE" == FILE:* ]]; then
            CACHE_FILE=${TICKET_CACHE#FILE:}
            echo "Detected FILE format at: $CACHE_FILE"
            echo ""
            echo -e "${GREEN}Suggested .env configuration:${NC}"
            echo "----------------------------------------"
            echo "# Add to platform-bootstrap/.env"
            if [ -n "$DETECTED_DOMAIN" ]; then
                echo "COMPANY_DOMAIN=$DETECTED_DOMAIN"
            elif [ -n "$WINDOWS_DOMAIN" ]; then
                echo "COMPANY_DOMAIN=$WINDOWS_DOMAIN"
            else
                echo "COMPANY_DOMAIN=COMPANY.COM  # Replace with your actual domain"
            fi
            echo "KERBEROS_CACHE_TYPE=FILE"

            CACHE_DIR=$(dirname "$CACHE_FILE")
            CACHE_NAME=$(basename "$CACHE_FILE")

            if [[ "$CACHE_DIR" == "$HOME"* ]]; then
                RELATIVE_PATH=${CACHE_DIR#$HOME}
                echo "KERBEROS_CACHE_PATH=\${HOME}$RELATIVE_PATH"
            else
                echo "KERBEROS_CACHE_PATH=$CACHE_DIR"
            fi
            echo "KERBEROS_CACHE_TICKET=$CACHE_NAME"
            echo "----------------------------------------"
            echo ""
            echo "After updating .env, get a fresh ticket:"
            # Use detected values for kinit suggestion
            if [ -n "$WINDOWS_USERNAME" ] && [ -n "${DETECTED_DOMAIN:-$WINDOWS_DOMAIN}" ]; then
                echo "  kinit ${WINDOWS_USERNAME}@${DETECTED_DOMAIN:-$WINDOWS_DOMAIN}"
            elif [ -n "${DETECTED_DOMAIN:-$WINDOWS_DOMAIN}" ]; then
                echo "  kinit YOUR_USERNAME@${DETECTED_DOMAIN:-$WINDOWS_DOMAIN}"
            else
                echo "  kinit YOUR_USERNAME@DOMAIN.COM"
            fi
        else
            # Truly unknown format
            echo "Unable to parse ticket cache format: $TICKET_CACHE"
            echo ""
            echo "Please manually configure your .env with:"
            echo "----------------------------------------"
            echo "COMPANY_DOMAIN=YOUR_DOMAIN.COM"
            echo "KERBEROS_CACHE_TYPE=FILE  # or DIR"
            echo "KERBEROS_CACHE_PATH=/path/to/ticket/directory"
            echo "KERBEROS_CACHE_TICKET=ticket_filename"
            echo "----------------------------------------"
        fi
    fi
else
    echo -e "${RED}❌ No Kerberos tickets found${NC}"
    echo ""
    echo "First, get a Kerberos ticket:"
    echo -n "1. Run: "
    if [ -n "$WINDOWS_USERNAME" ] && [ -n "$WINDOWS_DOMAIN" ]; then
        echo "kinit ${WINDOWS_USERNAME}@${WINDOWS_DOMAIN}"
    elif [ -n "$WINDOWS_DOMAIN" ]; then
        echo "kinit YOUR_USERNAME@${WINDOWS_DOMAIN}"
    else
        echo "kinit YOUR_USERNAME@DOMAIN.COM"
    fi
    echo "2. Enter your password"
    echo "3. Run this diagnostic again to get .env values"
fi

# 6. Additional Information
echo -e "\n${BLUE}=== 6. ADDITIONAL INFORMATION ===${NC}"

if [ -n "$DETECTED_CACHE_TYPE" ]; then
    echo -e "${GREEN}✓ Configuration detected successfully!${NC}"
    echo ""
    echo "Your ticket format: $DETECTED_CACHE_TYPE"
    if [[ "$DETECTED_CACHE_TYPE" == "DIR" ]]; then
        echo "  This is a directory-based ticket collection."
        echo "  Multiple tickets can be stored for different services."
    elif [[ "$DETECTED_CACHE_TYPE" == "FILE" ]]; then
        echo "  This is a single-file ticket format."
        echo "  Standard and widely compatible."
    fi
    echo ""
    echo "📖 For detailed information about ticket formats and options, see:"
    echo "   docs/kerberos-diagnostic-guide.md"
elif [ -n "$TICKET_CACHE" ]; then
    if [[ "$TICKET_CACHE" == DIR::* ]]; then
        echo -e "${YELLOW}⚠️  Directory collection detected but no ticket files found${NC}"
        echo ""
        echo "This usually means your tickets have expired or haven't been created yet."
        echo "Try getting a fresh ticket:"
        if [ -n "$WINDOWS_USERNAME" ] && [ -n "$WINDOWS_DOMAIN" ]; then
            echo "   kinit ${WINDOWS_USERNAME}@${WINDOWS_DOMAIN}"
        elif [ -n "$WINDOWS_DOMAIN" ]; then
            echo "   kinit YOUR_USERNAME@${WINDOWS_DOMAIN}"
        else
            echo "   kinit YOUR_USERNAME@DOMAIN.COM"
        fi
        echo ""
        echo "Then run this diagnostic again."
    fi
fi

# 7. Test Commands
echo -e "\n${BLUE}=== 7. TEST COMMANDS ===${NC}"

if [ -n "$DETECTED_CACHE_TYPE" ]; then
    echo "Your Kerberos is configured! Next steps:"
    echo ""
    echo "1. Save the .env configuration shown above"
    echo "2. Start platform services:"
    echo "   cd platform-bootstrap"
    echo "   make platform-start"
    echo ""
    echo "3. Test ticket sharing (Option 1 - Simple):"
    echo "   make test-kerberos-simple"
    echo ""
    echo "4. Test SQL Server connection (Option 2 - Full):"
    echo ""
    echo "   First, identify your SQL Server:"
    echo "   - Ask your DBA for server hostname and a test database"
    echo "   - Or check your existing connection strings"
    echo ""
    echo "   Then run this exact command (replace SERVER and DB):"
    echo "   docker run --rm \\"
    echo "     --network platform_network \\"
    echo "     -v platform_kerberos_cache:/krb5/cache:ro \\"
    echo "     -v \$(pwd)/test_kerberos.py:/app/test_kerberos.py \\"
    echo "     -e KRB5CCNAME=/krb5/cache/krb5cc \\"
    echo "     -e SQL_SERVER=\"YOUR_SERVER.company.com\" \\"
    echo "     -e SQL_DATABASE=\"YOUR_DATABASE\" \\"
    echo "     python:3.11-alpine \\"
    echo "     sh -c \"apk add --no-cache krb5 gcc musl-dev unixodbc-dev && \\"
    echo "            pip install --no-cache-dir pyodbc && \\"
    echo "            python /app/test_kerberos.py\""
    echo ""
    echo "   Or use the interactive helper:"
    echo "   ./test-kerberos.sh"
else
    echo "Try these commands in order:"
    echo ""
    echo "1. Ensure Docker setup is correct:"
    echo "   docker network create platform_network"
    echo "   docker volume create platform_kerberos_cache"
    echo ""
    echo "2. Get a fresh Kerberos ticket (use standard location):"
    echo "   export KRB5CCNAME=FILE:/tmp/krb5cc_\$(id -u)"
    if [ -n "$WINDOWS_USERNAME" ] && [ -n "$WINDOWS_DOMAIN" ]; then
        echo "   kinit ${WINDOWS_USERNAME}@${WINDOWS_DOMAIN}"
    elif [ -n "$WINDOWS_DOMAIN" ]; then
        echo "   kinit YOUR_USERNAME@${WINDOWS_DOMAIN}"
    else
        echo "   kinit YOUR_USERNAME@DOMAIN.COM"
    fi
    echo ""
    echo "3. Run this diagnostic again to get .env values:"
    echo "   ./diagnose-kerberos.sh"
    echo ""
    echo "4. Start platform services:"
    echo "   make platform-start"
    echo ""
    echo "5. Test the connection:"
    echo "   make test-kerberos-simple"
fi

echo -e "\n${GREEN}Diagnostic complete!${NC}"
