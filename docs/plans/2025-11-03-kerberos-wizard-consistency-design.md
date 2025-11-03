# Kerberos Sidecar Wizard Consistency Update Design

## Overview
Update the Kerberos sidecar wizard to be consistent with the platform Postgres and Pagila wizards, using section/subsection headers and integrating the new connection test containers (postgres-test and sqlcmd-test).

## Design Decisions

### Architecture Choice
- **Selected**: Separate Test Sections approach
- Two distinct subsections for SQL Server and PostgreSQL connection tests
- Each with its own prompts and actions
- Refactors existing progressive tests into targeted database tests

### Test Container Strategy
- **Selected**: Reference Existing containers
- Assumes postgres-test and sqlcmd-test are configured by base_platform
- No duplicate container configuration in Kerberos wizard
- Respects custom container names from prebuilt images

### Test Timing
- **Selected**: Progressive after Service Start
- Tests run after Kerberos sidecar is operational
- Only execute if user has remote servers to test
- Validates ticket attachment to test containers

## Section Structure

### Main Section
- **Header**: "Kerberos Configuration" (50 `=` chars)
- Displayed after service detection

### Subsections
1. **Kerberos Domain Setup** (50 `-` chars)
   - Domain input and validation
   - Principal configuration

2. **Container Configuration** (50 `-` chars)
   - Image selection (prebuilt vs base)
   - Container setup

3. **SQL Server Connection Test** (conditional)
   - Only if user has SQL Server to test
   - FQDN input
   - Connection validation with diagnostics

4. **PostgreSQL Connection Test** (conditional)
   - Only if user has PostgreSQL to test
   - FQDN input
   - Connection validation with diagnostics

## Connection Test Flow

### SQL Server Test
1. Prompt: "Do you have a SQL Server instance to test?"
2. If yes → Get FQDN
3. Launch sqlcmd-test container with ticket mount
4. Run sqlcmd connection test
5. Display results with diagnostics

### PostgreSQL Test
1. Prompt: "Do you have a PostgreSQL instance to test?"
2. If yes → Get FQDN
3. Launch postgres-test container with ticket mount
4. Run psql connection test
5. Display results with diagnostics

## Error Diagnostics

### Diagnostic Levels
1. **Basic**: Connection result with parsed errors
2. **Detailed**: Auto-triggered on failure
   - Ticket validation (klist)
   - krb5.conf verification
   - DNS checks
   - Network connectivity
   - SPN validation
3. **Verbose Debug**: Optional extended diagnostics
   - KRB5_TRACE output
   - Full negotiation logs

### krb5.conf Integration
Parse and validate:
- Realm configuration
- KDC accessibility
- Domain mappings
- Encryption types

### Error Categories
- **Authentication**: Ticket/SPN/keytab issues
- **Network**: DNS/firewall/connectivity
- **Configuration**: krb5.conf problems
- **Container**: Mount/permission issues

### Output Format
```
❌ Connection Failed
━━━━━━━━━━━━━━━━━━━
Primary Error: [specific error]
Kerberos Status: [ticket status]
Configuration Check:
  ✓/✗ [validation items]

Suggested Fix:
  [actionable steps]

Run extended diagnostics? (y/n)
```

## Implementation Structure

### New Display Actions
- `display_kerberos_header()`
- `display_domain_setup_header()`
- `display_container_config_header()`
- `display_sql_test_header()`
- `display_postgres_test_header()`

### Test Actions
- `prompt_sql_server_test()`
- `test_sql_server_connection()`
- `prompt_postgres_test()`
- `test_postgres_connection()`

### Diagnostic Actions
- `parse_krb5_config()`
- `validate_kerberos_realm()`
- `diagnose_connection_failure()`
- `run_extended_diagnostics()`

### Return Structure
```python
{
    'success': bool,
    'error_type': 'auth|network|config|container',
    'error_details': str,
    'diagnostics': dict,
    'suggestions': list
}
```

## Wizard Flow Updates

### spec.yaml Changes
1. Add header display actions at section boundaries
2. Replace progressive test section with:
   - SQL Server test prompt → conditional test flow
   - PostgreSQL test prompt → conditional test flow
3. Update complete_configuration to summarize test results

### Backward Compatibility
- Existing configuration preserved
- Progressive test diagnostics still available via command line
- New structure is additive, not breaking

## Testing Requirements

### Unit Tests
- Header display formatting
- Connection test execution
- Error parsing and categorization
- Diagnostic output generation

### Integration Tests
- Full wizard flow with both test types
- Failure scenarios with diagnostic triggers
- Custom container name handling
- krb5.conf validation logic

## Benefits

1. **Consistency**: Matches base_platform and Pagila wizard patterns
2. **Clarity**: Clear visual sections guide users
3. **Flexibility**: Optional tests only when needed
4. **Diagnostics**: Comprehensive error analysis with actionable fixes
5. **Maintainability**: Structured approach easier to extend

## Next Steps

1. Set up git worktree for isolated development
2. Implement display actions
3. Refactor progressive tests into separate database tests
4. Add diagnostic parsing for krb5.conf
5. Update spec.yaml with new flow
6. Write comprehensive tests
7. Document usage in README