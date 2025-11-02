# Phase 2: Test Container Configuration - TDD Implementation Plan

NOTE: This plan references .env.example which has since been removed. The platform now uses ./platform setup wizard and platform-config.yaml instead.

> **For Claude:** Use superpowers:subagent-driven-development for parallel TDD execution.

**Master Branch:** `feature/test-container-config` (PR-ready branch, all task worktrees inherit from this)

**Execution Model:** Each task executed in dedicated worktree with Red/Green/Review sub-phases, then merged back to master branch.

---

## Task 1: Test Container Dockerfiles

**Worktree:** `.worktrees/task-1-dockerfiles` (from `feature/test-container-config`)

### Task 1a: RED - Verify Migration Needed
- Read existing `kerberos/kerberos-sidecar/Dockerfile.postgres-test`
- Read existing `kerberos/kerberos-sidecar/Dockerfile.sqlcmd-test`
- Document what needs to change (BASE_IMAGE arg, unixODBC, non-root user, remove MSSQL_TOOLS_URL)
- Commit plan

### Task 1b: GREEN - Create New Dockerfiles
- Create `platform-infrastructure/test-containers/postgres-test/Dockerfile`
  - Add BASE_IMAGE arg (default: alpine:latest)
  - Add unixODBC packages
  - Add non-root user (testuser, uid 10001)
  - Keep all existing GSSAPI functionality
- Create `platform-infrastructure/test-containers/sqlcmd-test/Dockerfile`
  - Add BASE_IMAGE arg (default: alpine:latest)
  - Remove MSSQL_TOOLS_URL arg (simplification)
  - Add non-root user (testuser, uid 10001)
  - Keep FreeTDS + unixODBC
- Test build both: `docker build -f platform-infrastructure/test-containers/postgres-test/Dockerfile -t test-postgres .`
- Commit

### Task 1c: REVIEW - Code Review
- Launch code-reviewer subagent
- Verify Dockerfiles follow best practices
- Verify non-root users work
- Merge to `feature/test-container-config`

---

## Task 2: Wizard Sub-Spec

**Worktree:** `.worktrees/task-2-wizard-spec` (from `feature/test-container-config`)

### Task 2a: RED - Write Failing Spec Tests
- Create `wizard/services/base_platform/tests/test_test_containers_spec.py`
- Tests for:
  - Sub-spec file exists
  - Sub-spec loads
  - Has postgres_test.prebuilt step
  - Has postgres_test.image step
  - Has sqlcmd_test.prebuilt step
  - Has sqlcmd_test.image step
  - Has save_test_config action
- Run tests - EXPECT FAIL (sub-spec doesn't exist yet)
- Commit

### Task 2b: GREEN - Create Sub-Spec
- Create `wizard/services/base_platform/test-containers-spec.yaml`
- Follow Kerberos pattern (IMAGE + PREBUILT boolean)
- Steps:
  1. postgres_test_prebuilt (boolean, default: false)
  2. postgres_test_image (string, default: alpine:latest)
  3. sqlcmd_test_prebuilt (boolean, default: false)
  4. sqlcmd_test_image (string, default: alpine:latest)
  5. save_test_config (action: base_platform.save_test_container_config)
- Run tests - EXPECT PASS
- Commit

### Task 2c: REVIEW - Code Review
- Launch code-reviewer subagent
- Verify follows Kerberos pattern
- Verify all state keys correct
- Merge to `feature/test-container-config`

---

## Task 3: Wizard Actions

**Worktree:** `.worktrees/task-3-wizard-actions` (from `feature/test-container-config`)

### Task 3a: RED - Write Failing Action Tests
- Create `wizard/services/base_platform/tests/test_test_containers_actions.py`
- Tests for `invoke_test_container_spec`:
  - Function exists
  - Loads sub-spec
  - Executes sub-spec
  - Returns False if sub-spec not found
- Tests for `save_test_container_config`:
  - Function exists
  - Saves postgres_test config to platform-config.yaml
  - Saves sqlcmd_test config to platform-config.yaml
  - Saves to .env (IMAGE_POSTGRES_TEST, POSTGRES_TEST_PREBUILT, etc.)
  - Uses defaults if not configured
- Run tests - EXPECT FAIL (actions don't exist yet)
- Commit

### Task 3b: GREEN - Implement Actions
- Add to `wizard/services/base_platform/actions.py`:
  - `invoke_test_container_spec(state, console)` - loads and executes sub-spec
  - `save_test_container_config(state, console)` - saves config to yaml + env
- Run tests - EXPECT PASS
- Commit

### Task 3c: REVIEW - Code Review
- Launch code-reviewer subagent
- Verify actions follow wizard patterns
- Verify config saves correctly
- Merge to `feature/test-container-config`

---

## Task 4: Main Spec Integration

**Worktree:** `.worktrees/task-4-main-spec` (from `feature/test-container-config`)

### Task 4a: RED - Write Integration Test
- Add test to `wizard/services/base_platform/tests/test_spec.py`:
  - `test_spec_has_configure_test_containers_step`
  - Verify step exists after postgres_start
  - Verify calls invoke_test_container_spec action
- Run test - EXPECT FAIL (step doesn't exist)
- Commit

### Task 4b: GREEN - Add Step to Spec
- Edit `wizard/services/base_platform/spec.yaml`
- Change `postgres_start.next` from `finish` to `configure_test_containers`
- Add new step:
  ```yaml
  - id: configure_test_containers
    type: action
    action: base_platform.invoke_test_container_spec
    next: finish
  ```
- Run test - EXPECT PASS
- Commit

### Task 4c: REVIEW - Code Review
- Launch code-reviewer subagent
- Verify integration correct
- Merge to `feature/test-container-config`

---

## Task 5: Makefile Build Targets

**Worktree:** `.worktrees/task-5-makefile` (from `feature/test-container-config`)

### Task 5a: RED - Verify Targets Needed
- Check root Makefile - confirm no build-postgres-test or build-sqlcmd-test
- Document what targets need to do (build vs prebuilt logic)
- Commit plan

### Task 5b: GREEN - Add Makefile Targets
- Add to root `Makefile`:
  ```makefile
  build-postgres-test:
      @source platform-bootstrap/.env 2>/dev/null || true && \
      if [ "$${POSTGRES_TEST_PREBUILT}" = "true" ]; then \
          docker pull $${IMAGE_POSTGRES_TEST} && \
          docker tag $${IMAGE_POSTGRES_TEST} platform/postgres-test:latest; \
      else \
          docker build \
            -f platform-infrastructure/test-containers/postgres-test/Dockerfile \
            --build-arg BASE_IMAGE=$${IMAGE_POSTGRES_TEST:-alpine:latest} \
            -t platform/postgres-test:latest \
            platform-infrastructure/test-containers/postgres-test/; \
      fi

  build-sqlcmd-test:
      # Similar for sqlcmd

  build-test-containers: build-postgres-test build-sqlcmd-test
  ```
- Test: Create dummy .env, run `make build-postgres-test`
- Commit

### Task 5c: REVIEW - Code Review
- Launch code-reviewer subagent
- Verify targets work for both modes
- Merge to `feature/test-container-config`

---

## Task 6: Environment Configuration

**Worktree:** `.worktrees/task-6-env-config` (from `feature/test-container-config`)

### Task 6a: RED - Verify Missing Config
- Check `platform-bootstrap/.env.example`
- Confirm no test container configuration
- Document what needs to be added
- Commit

### Task 6b: GREEN - Add Configuration
- Add to `platform-bootstrap/.env.example`:
  ```bash
  # Test Containers (Base Platform)
  IMAGE_POSTGRES_TEST=alpine:latest
  POSTGRES_TEST_PREBUILT=false
  IMAGE_SQLCMD_TEST=alpine:latest
  SQLCMD_TEST_PREBUILT=false
  ```
- Add documentation comments
- Add corporate examples
- Commit

### Task 6c: REVIEW - Code Review
- Launch code-reviewer subagent
- Verify documentation clear
- Merge to `feature/test-container-config`

---

## Task 7: Documentation - directory-structure.md

**Worktree:** `.worktrees/task-7-docs-structure` (from `feature/test-container-config`)

### Task 7a: RED - Identify Gaps
- Read `docs/directory-structure.md`
- Document missing:
  - Architecture layers explanation
  - platform-infrastructure/ section
  - wizard/ section
  - test-containers/ subsection
- Commit plan

### Task 7b: GREEN - Add Documentation
- Add architecture layers section
- Add platform-infrastructure/ with test-containers explained
- Add wizard/ section
- Update navigation table
- Commit

### Task 7c: REVIEW - Code Review
- Launch code-reviewer subagent
- Verify documentation clear and complete
- Merge to `feature/test-container-config`

---

## Task 8: Documentation - platform-infrastructure/README.md

**Worktree:** `.worktrees/task-8-docs-infra` (from `feature/test-container-config`)

### Task 8a: RED - Identify Missing Content
- Read `platform-infrastructure/README.md`
- Confirm no test containers section
- Document what to add
- Commit

### Task 8b: GREEN - Add Test Containers Section
- Add comprehensive test containers documentation:
  - postgres-test specs and usage
  - sqlcmd-test specs and usage
  - Configuration via wizard
  - Build modes (build vs prebuilt)
  - Example commands
- Commit

### Task 8c: REVIEW - Code Review
- Launch code-reviewer subagent
- Verify examples work
- Merge to `feature/test-container-config`

---

## Task 9: Integration Testing

**Worktree:** `.worktrees/task-9-integration` (from `feature/test-container-config`)

### Task 9a: RED - Write Integration Test Script
- Create `tests/integration/test_test_container_build.sh`
- Tests:
  - Build postgres-test from alpine:latest
  - Verify psql, klist present
  - Build sqlcmd-test from alpine:latest
  - Verify sqlcmd, odbcinst present
  - Test prebuilt mode (tag + retag)
- Don't run yet (Dockerfiles might not build)
- Commit

### Task 9b: GREEN - Fix Any Build Issues
- Run integration tests
- Fix any Dockerfile issues
- Ensure all tests pass
- Commit

### Task 9c: REVIEW - Code Review
- Launch code-reviewer subagent
- Verify comprehensive coverage
- Merge to `feature/test-container-config`

---

## Task 10: Cleanup Old Dockerfiles

**Worktree:** `.worktrees/task-10-cleanup` (from `feature/test-container-config`)

### Task 10a: RED - Verify Old Files Exist
- Confirm `kerberos/kerberos-sidecar/Dockerfile.postgres-test` exists
- Confirm `kerberos/kerberos-sidecar/Dockerfile.sqlcmd-test` exists
- Verify new Dockerfiles work (run integration tests)
- Commit verification

### Task 10b: GREEN - Remove Old Files
- `git rm kerberos/kerberos-sidecar/Dockerfile.postgres-test`
- `git rm kerberos/kerberos-sidecar/Dockerfile.sqlcmd-test`
- Run integration tests again - EXPECT PASS (uses new locations)
- Commit

### Task 10c: REVIEW - Code Review
- Launch code-reviewer subagent
- Verify nothing references old paths
- Merge to `feature/test-container-config`

---

## Task 11: Final Verification

**Worktree:** `.worktrees/task-11-final` (from `feature/test-container-config`)

### Task 11a: Run All Tests
- `python -m pytest wizard/services/base_platform/tests/ -v`
- `./tests/integration/test_test_container_build.sh`
- `make build-test-containers`
- Document results
- Commit

### Task 11b: Verify Specs Load
- Test main spec loads
- Test sub-spec loads
- Commit verification

### Task 11c: Final Code Review
- Launch final code-reviewer subagent for entire implementation
- Address any remaining issues
- Merge to `feature/test-container-config`

---

## Aggregate and PR

After all tasks complete on `feature/test-container-config`:

1. Push master branch: `git push origin feature/test-container-config`
2. Create PR: `gh pr create --base main --title "feat: Add test container configuration (Phase 2)"`
3. After merge, cleanup: `./git-cleanup-audit.py`

---

## Parallelization Strategy

Tasks that can run in parallel (independent):
- Task 1 (Dockerfiles) ← Start first
- Task 2 (Wizard spec) ← Depends on nothing
- Task 6 (Env config) ← Depends on nothing
- Task 7 (docs: directory-structure) ← Depends on nothing
- Task 8 (docs: infrastructure README) ← Depends on Task 1

Tasks that must run sequentially:
- Task 3 (Actions) ← Depends on Task 2 (needs sub-spec)
- Task 4 (Main spec) ← Depends on Task 3 (needs actions)
- Task 5 (Makefile) ← Depends on Task 1 (needs Dockerfiles)
- Task 9 (Integration tests) ← Depends on Tasks 1, 5
- Task 10 (Cleanup) ← Depends on Task 9
- Task 11 (Final verification) ← Depends on all others

**Maximum Parallelism:** Can run Tasks 1, 2, 6, 7 simultaneously to start.
