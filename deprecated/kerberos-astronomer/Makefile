# Makefile for Kerberos Sidecar Platform Component

.PHONY: help build validate test clean deploy

# Variables
SIDECAR_IMAGE = kerberos-sidecar:latest
ASTRONOMER_IMAGE = astronomer-kerberos:latest
REGISTRY_URL ?= registry.localhost

help: ## Show this help message
	@echo "Kerberos Sidecar Platform Component"
	@echo "===================================="
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

validate: ## Validate Kerberos configuration
	@chmod +x scripts/validate-kerberos.sh
	@./scripts/validate-kerberos.sh

build-sidecar: ## Build Kerberos sidecar image
	docker build -f Dockerfile.kerberos-sidecar -t $(SIDECAR_IMAGE) .
	@echo "✓ Kerberos sidecar image built: $(SIDECAR_IMAGE)"

build-astronomer: ## Build Astronomer image with Kerberos support
	docker build -f Dockerfile.astronomer-kerberos -t $(ASTRONOMER_IMAGE) .
	@echo "✓ Astronomer Kerberos image built: $(ASTRONOMER_IMAGE)"

build: build-sidecar build-astronomer ## Build all images

test-local: ## Start local test environment with KDC
	docker-compose -f docker-compose.kdc-test.yml up -d
	@echo "✓ Local test environment started"
	@echo "  View logs: docker-compose -f docker-compose.kdc-test.yml logs -f"

start: ## Start production environment
	docker-compose -f docker-compose.override.yml up -d
	@echo "✓ Production environment started"
	@echo "  View logs: docker-compose logs -f kerberos-sidecar"

stop: ## Stop all environments
	docker-compose -f docker-compose.override.yml down
	docker-compose -f docker-compose.kdc-test.yml down
	@echo "✓ All environments stopped"

logs: ## View sidecar logs
	docker-compose logs -f kerberos-sidecar

status: ## Check ticket status
	@echo "Checking Kerberos ticket status..."
	@docker exec kerberos-sidecar klist || echo "No valid ticket or sidecar not running"

push: build ## Push images to registry
	docker tag $(SIDECAR_IMAGE) $(REGISTRY_URL)/platform/$(SIDECAR_IMAGE)
	docker tag $(ASTRONOMER_IMAGE) $(REGISTRY_URL)/platform/$(ASTRONOMER_IMAGE)
	docker push $(REGISTRY_URL)/platform/$(SIDECAR_IMAGE)
	docker push $(REGISTRY_URL)/platform/$(ASTRONOMER_IMAGE)
	@echo "✓ Images pushed to $(REGISTRY_URL)"

clean: ## Clean up containers and volumes
	docker-compose -f docker-compose.override.yml down -v
	docker-compose -f docker-compose.kdc-test.yml down -v
	@echo "✓ Cleaned up containers and volumes"

test-connection: ## Test SQL Server connection
	@echo "Testing SQL Server connection..."
	@docker exec airflow-scheduler python -c "from mssql_kerberos_hook import MSSQLKerberosHook; hook = MSSQLKerberosHook('mssql_kerberos'); success, msg = hook.test_connection(); print(msg)"
