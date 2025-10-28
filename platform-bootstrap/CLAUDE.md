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

## Future Improvements

- Consider creating a Python equivalent of the formatting library for the wizard
- Add more comprehensive test coverage for edge cases
- Document all test scenarios in a central test plan