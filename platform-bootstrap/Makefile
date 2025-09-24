# Developer Platform Bootstrap Makefile
# ======================================
# Orchestrates local platform services for development

.PHONY: help all start stop status clean

# Configuration
REGISTRY_CACHE_PORT ?= 5000
REGISTRY_UI_PORT ?= 5080
COMPANY_DOMAIN ?= COMPANY.COM
ARTIFACTORY_URL ?= artifactory.company.com

# Detect if we have Artifactory access
HAS_ARTIFACTORY := $(shell curl -s -o /dev/null -w "%{http_code}" https://$(ARTIFACTORY_URL) | grep -q "200\|401" && echo "yes" || echo "no")

help: ## Show this help message
	@echo "Developer Platform Bootstrap"
	@echo "============================"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick Start:"
	@echo "  make install        # Install prerequisites"
	@echo "  make platform-start # Start platform services"
	@echo "  make status        # Check everything is running"

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

platform-start: registry-start kerberos-start mock-start ## Start all platform services
	@echo "✓ Platform services started"
	@echo ""
	@echo "Access points:"
	@echo "  Registry:      http://localhost:$(REGISTRY_CACHE_PORT)"
	@echo "  Registry UI:   http://localhost:$(REGISTRY_UI_PORT)"
	@echo "  Mock Delinea:  https://localhost:8443"
	@echo ""
	@echo "Next: astro dev init my-project"

platform-stop: registry-stop kerberos-stop mock-stop ## Stop all platform services
	@echo "✓ Platform services stopped"

platform-status: ## Check status of platform services
	@echo "Platform Services Status:"
	@echo "========================"
	@docker-compose -f local-registry-cache.yml ps
	@docker-compose -f developer-kerberos-standalone.yml ps
	@echo ""
	@make registry-test
	@make kerberos-test

# ==========================================
# Registry Cache
# ==========================================

registry-start: ## Start local registry cache
	@echo "Starting registry cache..."
ifeq ($(HAS_ARTIFACTORY),yes)
	@echo "  Artifactory detected, configuring as pull-through cache"
	@docker-compose -f local-registry-cache.yml up -d
else
	@echo "  No Artifactory access, using local-only registry"
	@docker run -d -p $(REGISTRY_CACHE_PORT):5000 --name registry-cache registry:2 2>/dev/null || true
endif
	@echo "✓ Registry cache started at localhost:$(REGISTRY_CACHE_PORT)"

registry-stop: ## Stop registry cache
	@docker-compose -f local-registry-cache.yml down 2>/dev/null || true
	@docker stop registry-cache 2>/dev/null || true
	@docker rm registry-cache 2>/dev/null || true

registry-test: ## Test registry is working
	@echo -n "Registry cache: "
	@curl -s http://localhost:$(REGISTRY_CACHE_PORT)/v2/_catalog >/dev/null 2>&1 && \
		echo "✓ Running" || echo "✗ Not running"

registry-list: ## List cached images
	@echo "Cached images:"
	@curl -s http://localhost:$(REGISTRY_CACHE_PORT)/v2/_catalog | jq -r '.repositories[]' 2>/dev/null || echo "  No images cached yet"

# ==========================================
# Kerberos Service
# ==========================================

kerberos-start: ## Start Kerberos platform service
	@echo "Starting Kerberos service..."
	@# Check if developer has existing ticket
	@if klist -s 2>/dev/null; then \
		echo "  Using existing Kerberos ticket"; \
	else \
		echo "  No ticket found, will prompt for password"; \
	fi
	@docker-compose -f developer-kerberos-standalone.yml up -d
	@echo "✓ Kerberos service started"

kerberos-stop: ## Stop Kerberos service
	@docker-compose -f developer-kerberos-standalone.yml down

kerberos-test: ## Test Kerberos ticket
	@echo -n "Kerberos service: "
	@docker exec kerberos-platform-service klist -s 2>/dev/null && \
		echo "✓ Valid ticket" || echo "✗ No valid ticket"

kerberos-refresh: ## Refresh Kerberos ticket
	@echo "Refreshing Kerberos ticket..."
	@docker exec -it kerberos-platform-service kinit $(USER)@$(COMPANY_DOMAIN)

# ==========================================
# Mock Services
# ==========================================

mock-start: ## Start mock services (Delinea, etc.)
	@echo "Starting mock services..."
	@docker-compose -f mock-services.yml up -d 2>/dev/null || true
	@echo "✓ Mock services started"

mock-stop: ## Stop mock services
	@docker-compose -f mock-services.yml down 2>/dev/null || true

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
	@docker run --rm \
		--network platform_network \
		-v platform_kerberos_cache:/krb5/cache:ro \
		-e KRB5CCNAME=/krb5/cache/krb5cc \
		localhost:$(REGISTRY_CACHE_PORT)/datakits/connection-tester:latest

debug-logs: ## Show logs from all platform services
	@echo "Platform service logs:"
	@docker-compose -f local-registry-cache.yml logs --tail=20
	@docker-compose -f developer-kerberos-standalone.yml logs --tail=20

# ==========================================
# Offline Mode
# ==========================================

offline-enable: ## Enable offline mode (use cached images only)
	@echo "Enabling offline mode..."
	@touch .offline-mode
	@echo "✓ Offline mode enabled - using cached images only"

offline-disable: ## Disable offline mode
	@rm -f .offline-mode
	@echo "✓ Offline mode disabled - will pull from Artifactory"

offline-cache-astronomer: ## Cache Astronomer images for offline work
	@echo "Caching Astronomer images..."
	@for image in ap-airflow:11.10.0 ap-airflow:11.9.0; do \
		echo "  Pulling $$image..."; \
		docker pull $(ARTIFACTORY_URL)/astronomer-certified/$$image; \
		docker tag $(ARTIFACTORY_URL)/astronomer-certified/$$image localhost:$(REGISTRY_CACHE_PORT)/astronomer-certified/$$image; \
		docker push localhost:$(REGISTRY_CACHE_PORT)/astronomer-certified/$$image; \
	done
	@echo "✓ Astronomer images cached"

# ==========================================
# Cleanup
# ==========================================

clean: platform-stop ## Clean up all platform services and volumes
	@echo "Cleaning up platform services..."
	@docker volume rm platform_kerberos_cache 2>/dev/null || true
	@docker volume rm registry_cache_data 2>/dev/null || true
	@docker volume rm redis_cache_data 2>/dev/null || true
	@echo "✓ Cleanup complete"

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
