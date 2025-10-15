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

install: ## Install prerequisites (Docker, Astronomer CLI, etc.)
	@echo "Installing prerequisites..."
	@./setup-scripts/install-prereqs.sh
	@echo "✓ Prerequisites installed"

configure: ## Configure environment (Artifactory, Kerberos, etc.)
	@echo "Configuring environment..."
	@./setup-scripts/configure-environment.sh
	@echo "✓ Environment configured"

validate: ## Validate environment is ready
	@echo "Validating environment..."
	@./setup-scripts/validate-environment.sh

# ==========================================
# Platform Services
# ==========================================

platform-start: kerberos-start ## Start all platform services
	@echo "✓ Platform services started"
	@echo ""
	@echo "Note: Docker caches images automatically - no registry service needed"
	@echo "Next: astro dev init my-project"
	@echo ""
	@echo "Optional: Start mock services with 'make mock-start' if needed"

platform-stop: kerberos-stop ## Stop all platform services
	@echo "✓ Platform services stopped"

platform-status: ## Check status of platform services
	@echo "Platform Services Status:"
	@echo "========================"
	@$(DOCKER_COMPOSE) ps 2>/dev/null || echo "No services running"
	@echo ""
	@make kerberos-test

# ==========================================
# Note: Registry Removed
# ==========================================
# Docker caches pulled images automatically in its native image store.
# No local registry service is needed for single-developer environments.
# See: deprecated/registry-implementations/ for historical reference.

# ==========================================
# Kerberos Service
# ==========================================

kerberos-start: ## Start Kerberos sidecar service
	@echo "Checking for Kerberos sidecar image..."
	@if ! docker images platform/kerberos-sidecar:latest --format "{{.Repository}}" | grep -q "platform/kerberos-sidecar"; then \
		echo "❌ Image not found (this is normal on first run)"; \
		echo ""; \
		echo "Building Kerberos sidecar (one-time setup, 2-3 minutes)..."; \
		echo ""; \
		cd kerberos-sidecar && $(MAKE) build || { \
			echo ""; \
			echo "❌ Build failed. Common issues:"; \
			echo ""; \
			echo "1. Network connectivity"; \
			echo "   - Check internet connection or VPN"; \
			echo "   - May need corporate Artifactory (see .env.example)"; \
			echo ""; \
			echo "2. Docker not running"; \
			echo "   - Run: docker info"; \
			echo ""; \
			echo "3. Insufficient disk space"; \
			echo "   - Run: docker system prune"; \
			echo ""; \
			echo "For detailed diagnostics, run:"; \
			echo "   cd kerberos-sidecar && make check-requirements"; \
			echo ""; \
			exit 1; \
		}; \
		echo ""; \
		echo "✓ Sidecar built successfully"; \
		echo ""; \
	else \
		echo "✓ Image found"; \
		echo ""; \
	fi
	@echo "Starting Kerberos sidecar..."
	@# Note: Sidecar obtains tickets via keytab or password (configured in docker-compose.yml)
	@$(DOCKER_COMPOSE) up -d developer-kerberos-service
	@echo "✓ Kerberos sidecar started"
	@echo ""
	@echo "To verify: docker logs kerberos-platform-service"
	@echo "To check ticket: docker exec kerberos-platform-service klist"

kerberos-stop: ## Stop Kerberos sidecar
	@$(DOCKER_COMPOSE) down 2>/dev/null || true
	@echo "✓ Kerberos sidecar stopped"

kerberos-test: ## Test Kerberos ticket
	@echo -n "Kerberos service: "
	@docker exec kerberos-platform-service klist -s 2>/dev/null && \
		echo "✓ Valid ticket" || echo "✗ No valid ticket"

kerberos-refresh: ## Refresh Kerberos ticket
	@echo "Refreshing Kerberos ticket..."
	@docker exec -it kerberos-platform-service kinit $(USER)@$(COMPANY_DOMAIN)

kerberos-setup: ## Interactive wizard to set up Kerberos from scratch (with logging)
	@./run-kerberos-setup.sh

kerberos-diagnose: ## Diagnose Kerberos configuration issues
	@./diagnose-kerberos.sh

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
	@./test-kerberos.sh

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
	@./test-kerberos.sh

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

clean: platform-stop ## Clean up platform services and volumes (keeps images)
	@echo "Cleaning up platform services..."
	@echo "1" | ./clean-slate.sh || true

clean-slate: ## Interactive cleanup (option to remove built images too)
	@./clean-slate.sh

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
