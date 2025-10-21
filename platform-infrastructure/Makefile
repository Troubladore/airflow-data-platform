# Platform Infrastructure Makefile
# =================================
# Shared foundational services for the data platform
# Provides: PostgreSQL (OLTP), platform_network
#
# This service is the foundation - always starts before other services

.PHONY: help start stop restart status logs clean

# Load configuration from .env if it exists
-include .env
export

DOCKER_COMPOSE := docker compose

help: ## Show this help message
	@echo "Platform Shared Infrastructure"
	@echo "=============================="
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -v "^help:" | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick start:"
	@echo "  1. cp .env.example .env  # Configure password"
	@echo "  2. make start            # Start shared infrastructure"
	@echo ""
	@echo "Note: This service is foundational - usually started automatically"
	@echo "      by platform-bootstrap orchestrator."

start: ## Start shared infrastructure
	@echo "Starting platform infrastructure..."
	@echo ""
	@if [ ! -f .env ]; then \
		echo "⚠️  No .env file found"; \
		echo "Create one: cp .env.example .env"; \
		echo "Then customize PLATFORM_DB_PASSWORD"; \
		exit 1; \
	fi
	@echo "Starting services..."
	@$(DOCKER_COMPOSE) up -d
	@echo ""
	@echo "✓ Platform infrastructure started"
	@echo ""
	@echo "Services:"
	@echo "  • PostgreSQL:      docker ps | grep platform-postgres"
	@echo "  • Network:         docker network inspect platform_network"
	@echo ""
	@echo "Databases (will be created on first startup):"
	@echo "  • openmetadata_db  - OpenMetadata metadata catalog"
	@echo "  • airflow_db       - Airflow metastore"
	@echo ""
	@echo "Connection info:"
	@echo "  Host: platform-postgres (from Docker network)"
	@echo "  User: platform_admin"
	@echo "  Password: (set in .env)"

stop: ## Stop shared infrastructure
	@echo "Stopping platform infrastructure..."
	@$(DOCKER_COMPOSE) down
	@echo "✓ Infrastructure stopped"

restart: stop start ## Restart infrastructure

status: ## Check infrastructure health
	@echo "Platform Infrastructure Status:"
	@echo "==============================="
	@echo ""
	@$(DOCKER_COMPOSE) ps
	@echo ""
	@echo "Health Check:"
	@echo -n "  PostgreSQL: "
	@docker exec platform-postgres pg_isready -U platform_admin >/dev/null 2>&1 && echo "✓ Ready" || echo "✗ Not ready"
	@echo ""
	@echo "Databases:"
	@docker exec platform-postgres psql -U platform_admin -lqt 2>/dev/null | grep -E "openmetadata_db|airflow_db" | awk '{print "  •", $$1}' || echo "  (databases not created yet)"

logs: ## Show service logs
	@$(DOCKER_COMPOSE) logs --tail=50 --follow

clean: ## Remove infrastructure (WARNING: deletes all platform databases!)
	@echo "⚠️  This will remove platform-postgres and ALL platform databases"
	@echo "   Affected: OpenMetadata metadata, Airflow metastore, etc."
	@echo ""
	@read -p "Are you sure? [y/N]: " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "Cancelled"; \
		exit 1; \
	fi
	@echo "Removing platform infrastructure..."
	@$(DOCKER_COMPOSE) down -v
	@docker network rm platform_network 2>/dev/null || true
	@echo "✓ Infrastructure removed (containers, volumes, network deleted)"
