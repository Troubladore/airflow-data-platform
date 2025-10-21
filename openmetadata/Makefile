# OpenMetadata Makefile
# =====================
# Standalone OpenMetadata metadata catalog service
#
# Usage:
#   make start    # Start OpenMetadata
#   make stop     # Stop OpenMetadata
#   make status   # Check service health
#   make logs     # Show service logs

.PHONY: help start stop restart status logs clean

# Load configuration from .env if it exists
-include .env
export

DOCKER_COMPOSE := docker compose

help: ## Show this help message
	@echo "OpenMetadata Standalone Service"
	@echo "==============================="
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -v "^help:" | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick start:"
	@echo "  1. make setup            # Guided setup (recommended)"
	@echo "     OR"
	@echo "     cp .env.example .env  # Manual configuration"
	@echo "  2. make start            # Start OpenMetadata"
	@echo "  3. Open http://localhost:8585"
	@echo "  4. Login: admin@open-metadata.org / admin"

setup: ## Run interactive setup wizard
	@./setup.sh

start: ## Start OpenMetadata services
	@echo "Starting OpenMetadata..."
	@echo ""
	@if [ ! -f .env ]; then \
		echo "⚠️  No .env file found"; \
		echo "Create one: cp .env.example .env"; \
		echo "Then customize passwords and settings"; \
		exit 1; \
	fi
	@echo "Starting services (this may take 2-3 minutes on first run)..."
	@$(DOCKER_COMPOSE) up -d
	@echo ""
	@echo "✓ OpenMetadata started"
	@echo ""
	@echo "Services:"
	@echo "  • PostgreSQL:      docker ps | grep platform-postgres"
	@echo "  • OpenSearch:       docker ps | grep openmetadata-opensearch"
	@echo "  • OpenMetadata UI: http://localhost:$(OPENMETADATA_PORT)"
	@echo "  • Login:           admin@open-metadata.org / admin"
	@echo ""
	@echo "Next steps:"
	@echo "  make status    # Check service health"
	@echo "  make logs      # View service logs"

stop: ## Stop OpenMetadata services
	@echo "Stopping OpenMetadata..."
	@$(DOCKER_COMPOSE) down
	@echo "✓ OpenMetadata stopped"

restart: stop start ## Restart OpenMetadata services

status: ## Check service health
	@echo "OpenMetadata Service Status:"
	@echo "============================="
	@echo ""
	@$(DOCKER_COMPOSE) ps
	@echo ""
	@echo "Health Checks:"
	@echo -n "  PostgreSQL: "
	@docker exec platform-postgres pg_isready -U platform_admin >/dev/null 2>&1 && echo "✓ Ready" || echo "✗ Not ready"
	@echo -n "  OpenSearch: "
	@curl -sf http://localhost:9200/_cluster/health >/dev/null 2>&1 && echo "✓ Healthy" || echo "✗ Not healthy"
	@echo -n "  OpenMetadata: "
	@curl -sf http://localhost:8586/healthcheck | grep -q '"healthy":true' 2>/dev/null && echo "✓ Healthy" || echo "✗ Not healthy"

logs: ## Show service logs
	@$(DOCKER_COMPOSE) logs --tail=50 --follow

clean: ## Remove OpenMetadata containers and volumes (WARNING: deletes data!)
	@echo "⚠️  This will remove all OpenMetadata containers and volumes"
	@echo "   All metadata and catalog data will be lost!"
	@echo ""
	@read -p "Are you sure? [y/N]: " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "Cancelled"; \
		exit 1; \
	fi
	@echo "Removing OpenMetadata..."
	@$(DOCKER_COMPOSE) down -v
	@echo "✓ OpenMetadata removed (containers and volumes deleted)"
