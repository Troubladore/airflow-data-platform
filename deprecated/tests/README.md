# Deprecated Tests

## Ansible Validators

The `validators/` directory contained Ansible playbook validators:
- `test-01-mkcert-binary-validator.yml`
- `test-atomic-validators.yml`
- `test-modular-composition.yml`

**Why deprecated**: We no longer use Ansible for platform automation. The simplified architecture uses standard Docker Compose and shell scripts.

## Current Testing Strategy

Tests now live within their respective components:
- **SQLModel Framework**: `sqlmodel-framework/tests/`
- **Runtime Environments**: Each environment has its own test suite
- **Platform Bootstrap**: Simple smoke tests via `make test`

This follows the principle of colocating tests with the code they test.
