# Development Notes for Claude Code

## Formatting Consistency

**ALWAYS** use the platform's formatting library for all shell scripts. The library is located at:
```
platform-bootstrap/lib/formatting.sh
```

### How to Use

In any new shell script, source the formatting library at the beginning:
```bash
#!/bin/bash
# Find repo root and source formatting library
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/platform-bootstrap/lib/formatting.sh"
```

### Available Functions

The formatting library provides consistent output functions:
- `print_header "Title"` - Major section headers
- `print_section "Section"` - Subsection headers
- `print_check "PASS|FAIL|WARN|INFO" "message"` - Status messages with symbols
- `print_error "message"` - Error messages
- `print_warning "message"` - Warning messages
- `print_info "message"` - Information messages
- `print_success "message"` - Success messages
- `print_step "number" "description"` - Step indicators
- `print_bullet "text"` - Bullet point lists
- `print_arrow "PASS|FAIL|WARN|INFO" "text"` - Arrow indicators with status
- `print_divider [length]` - Horizontal dividers
- `print_env_var "NAME" "value"` - Environment variable display

### Why This Matters

1. **Consistency**: All platform scripts use the same formatting, providing a unified user experience
2. **Accessibility**: The library handles NO_COLOR environment variable for terminal compatibility
3. **Maintenance**: Changes to formatting can be made in one place
4. **Professional**: Consistent formatting makes the platform look polished and well-designed

### DO NOT

- Create custom color variables in individual scripts
- Use raw ANSI escape codes
- Use echo -e with custom formatting
- Define duplicate formatting functions

### Examples

Instead of:
```bash
RED='\033[0;31m'
echo -e "${RED}Error: Something failed${NC}"
```

Use:
```bash
print_error "Something failed"
```

Instead of:
```bash
echo "✅ Test passed"
```

Use:
```bash
print_check "PASS" "Test passed"
```

## Test Scripts

All test scripts should follow the platform conventions:
1. Use the formatting library (as described above)
2. Place in the `tests/` directory
3. Make executable with `chmod +x`
4. Include comprehensive documentation in the script header
5. Use consistent function naming (log_*, test_*, check_*)
6. Exit with proper status codes (0 for success, 1 for failure)

## Custom Image Testing

When working with custom Docker images for enterprise environments:
- Use the `mock-corporate-image.py` utility for creating test images
- Test scenarios must cover all paths from issue #98
- Always verify clean-slate properly removes custom images
- Test both layered and prebuilt modes
- Validate complex registry paths with ports and deep nesting

## Handling Corporate Kerberos/Pagila Test Requests

When the user says: **"Can you make sure the corporate Kerberos path works?"** or similar:

### STOP AND THINK FIRST
1. Check what's currently running: `docker ps`
2. Check existing configuration: `ls -la platform-config.yaml platform-bootstrap/.env`
3. Check if test images exist: `docker images | grep mycorp`

### Complete Test Process

#### 1. Clean Slate First
```bash
# Use printf to provide all confirmations
printf "y\ny\ny\ny\ny\n" | ./platform clean-slate

# Verify cleanup
rm -f platform-config.yaml platform-bootstrap/.env
docker ps -a | grep platform  # Should be empty
```

#### 2. Ensure Test Images Exist
```bash
# Check test image status
cd /home/eru_admin/repos/airflow-data-platform
python3 mock-corporate-image.py test-status

# If not all ready, create them
python3 mock-corporate-image.py test-setup
```

#### 3. Key Corporate Test Images
The user wants to test these specific corporate registry paths:
- **PostgreSQL**: `mycorp.jfrog.io/docker-mirror/mycorp-approved-images/postgres/17.5:2025.10.01`
- **Kerberos Prebuilt**: `mycorp.jfrog.io/docker-mirror/mycorp-approved-images/kerberos-base:latest`
- **SQL Auth**: `mycorp.jfrog.io/docker-mirror/mycorp-approved-images/sql-auth-base:latest`
- **OpenMetadata**: `artifactory.corp.net/docker-public/openmetadata/server:1.5.11-approved`

#### 4. Run Platform Setup Interactively
Since the wizard has validation issues with complex paths, run interactively:
```bash
./platform setup
```

When prompted:
- Platform name: `corporate-test`
- Install PostgreSQL: `y`
- PostgreSQL image: Try the corporate one, if rejected use default: `postgres:17.5-alpine`
- Database settings: Use defaults or simple values
- Install OpenMetadata: `n` (unless testing that too)
- Install Kerberos: `y`
- Kerberos image: `mycorp.jfrog.io/docker-mirror/mycorp-approved-images/kerberos-base:latest`
- Kerberos mode: `prebuilt` (IMPORTANT!)
- Realm: `CORP.EXAMPLE.COM`
- KDC: `kdc.corp.example.com`
- Admin server: `kadmin.corp.example.com`

#### 5. Verify Kerberos is Working
```bash
# Check container is running
docker ps | grep kerberos

# Verify prebuilt packages work
docker exec kerberos-platform klist -V

# Check configuration was saved
grep "kerberos-base:latest" platform-config.yaml
grep "prebuilt" platform-bootstrap/.env
```

#### 6. Test Clean-Slate Removes Everything
```bash
# Run clean-slate with confirmations
printf "y\ny\ny\ny\ny\n" | ./platform clean-slate

# Verify corporate images can be removed
docker images | grep mycorp  # Should still exist but not be in use
```

### Key Points to Remember
1. **The wizard may reject complex image paths** - This is a known issue
2. **Always use PREBUILT mode** for corporate Kerberos images
3. **The test scripts work** but wizard validation is stricter
4. **Check before acting** - Don't assume clean state

### Alternative: Use Test Scripts
If the wizard is problematic, use the comprehensive tests:
```bash
# These scripts handle everything automatically
./tests/test-custom-image-validation.sh
./tests/test-platform-integration.sh
./tests/test-clean-slate-images.sh
```

## Future Improvements

- Fix wizard validation to accept complex corporate registry paths
- Consider creating a Python equivalent of the formatting library for the wizard
- Add more comprehensive test coverage for edge cases
- Document all test scenarios in a central test plan