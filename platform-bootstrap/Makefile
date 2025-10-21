# Developer Platform Bootstrap Makefile
# ======================================
# Orchestrates local platform services for development

.PHONY: help all start stop status clean

# Configuration
# Load from .env file if it exists, otherwise use defaults
-include .env
export

COMPANY_DOMAIN ?= COMPANY.COM

# Use modern Docker Compose syntax (v2+)
DOCKER_COMPOSE := docker compose


help: ## Show this help message
	@echo "Developer Platform Bootstrap"
	@echo "============================"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick Start (90% of users):"
	@echo "  kinit USERNAME@DOMAIN  # Get Kerberos ticket (if using SQL Server)"
	@echo "  make platform-start    # Start ALL services (recommended)"
	@echo "  make platform-stop     # Stop everything when done"
	@echo ""
	@echo "Advanced (start specific services only):"
	@echo "  make kerberos-start    # Just Kerberos ticket sharing"
	@echo "  make mock-start        # Just mock services"

# ==========================================
# Installation & Setup
# ==========================================

setup: ## Run comprehensive platform setup wizard (recommended for first-time setup)
	@./setup-scripts/platform-setup-wizard.sh

setup-pagila: ## Setup pagila test database (idempotent)
	@./setup-scripts/setup-pagila.sh

setup-pagila-reset: ## Remove and reinstall pagila test database
	@./setup-scripts/setup-pagila.sh --reset

# ==========================================
# Platform Services
# ==========================================

platform-start: ## Start platform services (configured in .env)
	@echo "Starting platform services (configured in .env)..."
	@echo ""
	@if [ ! -f .env ]; then \
		echo "⚠️  No .env file found in platform-bootstrap/"; \
		echo "Create one: cp .env.example .env"; \
		exit 1; \
	fi
	@# Check what services are enabled
	@if [ "$(ENABLE_KERBEROS)" = "true" ]; then \
		echo "✓ Kerberos: ENABLED"; \
	else \
		echo "○ Kerberos: DISABLED"; \
	fi
	@if [ "$(ENABLE_OPENMETADATA)" = "true" ]; then \
		echo "✓ OpenMetadata: ENABLED"; \
	else \
		echo "○ OpenMetadata: DISABLED"; \
	fi
	@if [ "$(ENABLE_KERBEROS)" != "true" ] && [ "$(ENABLE_OPENMETADATA)" != "true" ]; then \
		echo ""; \
		echo "⚠️  No optional services enabled"; \
		echo "Infrastructure will still start (always needed for Airflow)"; \
	fi
	@echo ""
	@# ALWAYS start platform-infrastructure first (foundation)
	@echo "Starting platform infrastructure (always required)..."; \
	cd ../platform-infrastructure && $(MAKE) start || exit 1; \
	echo ""
	@# Start optional services
	@if [ "$(ENABLE_KERBEROS)" = "true" ]; then \
		echo "Starting Kerberos..."; \
		cd ../kerberos && $(MAKE) start || exit 1; \
		echo ""; \
	fi
	@if [ "$(ENABLE_OPENMETADATA)" = "true" ]; then \
		echo "Starting OpenMetadata..."; \
		cd ../openmetadata && $(MAKE) start || exit 1; \
		echo ""; \
	fi
	@echo "✓ Platform services started"
	@echo ""
	@echo "Active services:"
	@echo "  • Platform PostgreSQL: docker ps | grep platform-postgres (foundation)"
	@echo "  • Platform Network:    platform_network (shared)"
	@if [ "$(ENABLE_KERBEROS)" = "true" ]; then \
		echo "  • Kerberos Sidecar:    docker ps | grep kerberos-sidecar"; \
	fi
	@if [ "$(ENABLE_OPENMETADATA)" = "true" ]; then \
		echo "  • OpenMetadata UI:     http://localhost:8585"; \
		echo "  • Login:               admin@open-metadata.org / admin"; \
	fi
	@echo ""
	@echo "Configuration: Edit .env to enable/disable optional services"
	@echo "Status: make platform-status"

platform-stop: ## Stop all platform services
	@echo "Stopping platform services..."
	@# Stop optional services first
	@cd ../kerberos && $(MAKE) stop 2>/dev/null || true
	@cd ../openmetadata && $(MAKE) stop 2>/dev/null || true
	@# Stop infrastructure last
	@cd ../platform-infrastructure && $(MAKE) stop 2>/dev/null || true
	@echo "✓ Platform services stopped"

platform-status: ## Check status of platform services
	@echo "Platform Services Status:"
	@echo "========================"
	@echo ""
	@# Infrastructure status (always check - it's the foundation)
	@echo "Infrastructure (always running):"
	@cd ../platform-infrastructure && $(MAKE) status 2>/dev/null || echo "  Not running"
	@echo ""
	@# Optional services
	@if [ "$(ENABLE_KERBEROS)" = "true" ]; then \
		echo "Kerberos:"; \
		cd ../kerberos && $(MAKE) status 2>/dev/null || echo "  Not running"; \
		echo ""; \
	fi
	@if [ "$(ENABLE_OPENMETADATA)" = "true" ]; then \
		echo "OpenMetadata:"; \
		cd ../openmetadata && $(MAKE) status 2>/dev/null || echo "  Not running"; \
		echo ""; \
	fi

# ==========================================
# Note: Registry Removed
# ==========================================
# Docker caches pulled images automatically in its native image store.
# No local registry service is needed for single-developer environments.
# See: deprecated/registry-implementations/ for historical reference.

# ==========================================
# Kerberos Service (Individual Targets)
# ==========================================
# Note: Kerberos is included in 'platform-start' (always-on)
# These targets are for advanced use cases only

kerberos-start: ## Start Kerberos sidecar service
	@echo "Starting Kerberos sidecar..."
	@docker network create platform_network 2>/dev/null || true
	@docker volume create platform_kerberos_cache 2>/dev/null || true
	@echo "Checking for Kerberos sidecar image..."
	@if ! docker images platform/kerberos-sidecar:latest --format "{{.Repository}}" | grep -q "platform/kerberos-sidecar"; then \
		echo "Building Kerberos sidecar (one-time setup)..."; \
		cd kerberos-sidecar && $(MAKE) build || exit 1; \
	fi
	@$(DOCKER_COMPOSE) up -d developer-kerberos-service
	@echo "✓ Kerberos sidecar started"

kerberos-stop: ## Stop Kerberos sidecar
	@$(DOCKER_COMPOSE) -f docker-compose.yml -f docker-compose.openmetadata.yml down 2>/dev/null || true
	@echo "✓ Kerberos sidecar stopped"

kerberos-test: ## Test Kerberos ticket
	@echo -n "Kerberos service: "
	@docker exec kerberos-platform-service klist -s 2>/dev/null && \
		echo "✓ Valid ticket" || echo "✗ No valid ticket"

kerberos-refresh: ## Refresh Kerberos ticket
	@echo "Refreshing Kerberos ticket..."
	@docker exec -it kerberos-platform-service kinit $(USER)@$(COMPANY_DOMAIN)

kerberos-setup: ## Interactive wizard to set up Kerberos from scratch (with logging)
	@./dev-tools/run-kerberos-setup.sh

kerberos-diagnose: ## Diagnose Kerberos configuration issues
	@cd ../kerberos && ./diagnostics/diagnose-kerberos.sh

test-kerberos-simple: ## Test that Kerberos tickets are shared with containers
	@echo "Testing Kerberos ticket sharing..."
	@docker run --rm \
		--network platform_network \
		-v platform_kerberos_cache:/krb5/cache:ro \
		-v $$(pwd)/test_kerberos_simple.py:/app/test.py \
		-e KRB5CCNAME=/krb5/cache/krb5cc \
		python:3.11-alpine \
		sh -c "apk add --no-cache krb5 >/dev/null 2>&1 && python /app/test.py" && \
		echo "✅ SUCCESS: Kerberos tickets are being shared!" || \
		(echo "❌ FAILED: Check that 'make platform-start' has been run" && exit 1)

test-kerberos-full: ## Interactive test of SQL Server connection with Kerberos
	@./dev-tools/test-kerberos.sh

# ==========================================
# Mock Services
# ==========================================

mock-start: ## Start optional mock services (Delinea, etc.)
	@echo "Starting optional mock services..."
	@echo ""
	@echo "Note: Mock services are NOT required for Kerberos functionality"
	@echo "      Only start if you need to test Delinea integration"
	@echo ""
	@if [ ! -f docker-compose.mock-services.yml ]; then \
		echo "⚠️  docker-compose.mock-services.yml not found"; \
		echo "   Mock services not available"; \
	else \
		$(DOCKER_COMPOSE) -f docker-compose.mock-services.yml up -d 2>/dev/null || \
		echo "⚠️  Mock services failed to start (may need IMAGE_MOCKSERVER in .env)"; \
	fi
	@echo "✓ Mock services command completed"

mock-stop: ## Stop mock services
	@$(DOCKER_COMPOSE) -f docker-compose.mock-services.yml down 2>/dev/null || true

# ==========================================
# Developer Tools
# ==========================================

create-project: ## Create new Astronomer project from template
	@echo "Creating new Astronomer project..."
	@read -p "Project name: " project_name; \
	read -p "Template (bronze/silver/gold): " template; \
	astro dev init $$project_name --from-template $$template
	@echo "✓ Project created"

test-connection: ## Test SQL Server connection through Kerberos
	@echo "Testing SQL Server connection..."
	@./dev-tools/test-kerberos.sh

debug-logs: ## Show logs from all platform services
	@echo "Platform service logs:"
	@$(DOCKER_COMPOSE) logs --tail=20 2>/dev/null || true

# ==========================================
# Note: Offline Mode Removed
# ==========================================
# Docker automatically caches all pulled images locally.
# For offline development, simply pull images once while online:
#   docker pull <image>
# They remain cached until explicitly removed.

# ==========================================
# Cleanup
# ==========================================

# Granular cleanup (for iterative testing)
clean-openmetadata: ## Remove OpenMetadata services (asks about data volumes)
	@./setup-scripts/cleanup-openmetadata.sh

clean-pagila: ## Remove pagila test database (reuses setup script)
	@./setup-scripts/setup-pagila.sh --reset --yes

clean-kerberos: ## Remove only Kerberos sidecar (keeps volumes)
	@echo "Removing Kerberos sidecar..."
	@docker rm -f kerberos-platform-service 2>/dev/null || true
	@echo "✓ Kerberos sidecar removed (volume preserved)"
	@echo "To restart: make platform-start"

# Full cleanup
clean: platform-stop ## Clean up all platform services (interactive - asks about volumes)
	@echo "Cleaning up platform services..."
	@echo "1" | ./setup-scripts/clean-slate.sh || true

clean-slate: ## Interactive cleanup (guided prompts for all components)
	@./setup-scripts/clean-slate.sh

clean-all: clean-openmetadata clean-pagila clean-kerberos ## Remove all platform components and volumes
	@echo "Removing platform network..."
	@docker network rm platform_network 2>/dev/null || true
	@echo "✓ All platform services cleaned"

reset: clean ## Reset everything to fresh state
	@echo "Resetting platform..."
	@rm -rf ~/.astro
	@rm -f .offline-mode
	@echo "✓ Platform reset complete"

# ==========================================
# Development Workflow
# ==========================================

dev-start: platform-start ## Full developer startup sequence
	@echo ""
	@echo "Developer platform ready!"
	@echo ""
	@echo "Next steps:"
	@echo "1. Create a project: make create-project"
	@echo "2. Or clone existing: git clone <datakit-repo>"
	@echo "3. Start Airflow: cd <project> && astro dev start"

dev-stop: platform-stop ## Stop everything for the day
	@echo "Platform stopped. Have a great day!"

# ==========================================
# Troubleshooting
# ==========================================

doctor: ## Diagnose common issues
	@echo "Running platform diagnostics..."
	@./setup-scripts/doctor.sh

fix-permissions: ## Fix common permission issues
	@echo "Fixing permissions..."
	@sudo chown -R $(USER):$(USER) ~/.docker 2>/dev/null || true
	@sudo chown -R $(USER):$(USER) ~/.astro 2>/dev/null || true
	@echo "✓ Permissions fixed"

fix-network: ## Fix Docker network issues
	@echo "Fixing Docker networks..."
	@docker network prune -f
	@docker network create platform_network 2>/dev/null || true
	@echo "✓ Networks fixed"
