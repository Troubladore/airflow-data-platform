# Kerberos Sidecar Makefile
# ==========================
# Standalone Kerberos ticket sharing service
#
# Usage:
#   make build    # Build the sidecar image
#   make start    # Start Kerberos service
#   make stop     # Stop Kerberos service
#   make status   # Check service health

.PHONY: help build start stop restart status logs clean test

# Load configuration from .env if it exists
-include .env
export

DOCKER_COMPOSE := docker compose
IMAGE_NAME := platform/kerberos-sidecar:latest

help: ## Show this help message
	@echo "Kerberos Sidecar Service"
	@echo "========================"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -v "^help:" | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick start:"
	@echo "  1. make setup                # Guided setup (recommended - 11 validation steps)"
	@echo "     OR"
	@echo "     cp .env.example .env      # Manual configuration"
	@echo "     kinit USER@DOMAIN         # Get Kerberos ticket"
	@echo "  2. make build                # Build sidecar image (if needed)"
	@echo "  3. make start                # Start Kerberos sidecar"

setup: ## Run interactive Kerberos setup wizard (11 validation steps)
	@./setup.sh

build: ## Build the Kerberos sidecar image
	@echo "Building Kerberos sidecar image..."
	@cd kerberos-sidecar && $(MAKE) build
	@echo "✓ Kerberos sidecar image built: $(IMAGE_NAME)"

start: ## Start Kerberos service
	@echo "Starting Kerberos sidecar..."
	@echo ""
	@if [ ! -f .env ]; then \
		echo "⚠️  No .env file found"; \
		echo "Create one: cp .env.example .env"; \
		echo "Then customize COMPANY_DOMAIN and other settings"; \
		exit 1; \
	fi
	@if ! docker images $(IMAGE_NAME) --format "{{.Repository}}" | grep -q "platform/kerberos-sidecar"; then \
		echo "⚠️  Kerberos sidecar image not found"; \
		echo "Building image..."; \
		$(MAKE) build; \
	fi
	@echo "Starting service..."
	@$(DOCKER_COMPOSE) up -d
	@echo ""
	@echo "✓ Kerberos sidecar started"
	@echo ""
	@echo "Services:"
	@echo "  • Kerberos Sidecar: docker ps | grep kerberos-sidecar"
	@echo ""
	@echo "Next steps:"
	@echo "  make status    # Check service health"
	@echo "  make test      # Test ticket availability"
	@echo "  make logs      # View service logs"

stop: ## Stop Kerberos service
	@echo "Stopping Kerberos sidecar..."
	@$(DOCKER_COMPOSE) down
	@echo "✓ Kerberos sidecar stopped"

restart: stop start ## Restart Kerberos service

status: ## Check service health
	@echo "Kerberos Sidecar Status:"
	@echo "========================"
	@echo ""
	@$(DOCKER_COMPOSE) ps
	@echo ""
	@echo "Health Check:"
	@echo -n "  Kerberos: "
	@docker exec kerberos-sidecar klist -s 2>/dev/null && echo "✓ Valid ticket" || echo "✗ No valid ticket"

test: ## Test Kerberos ticket availability
	@echo "Testing Kerberos ticket..."
	@echo ""
	@if ! docker ps --format '{{.Names}}' | grep -q "^kerberos-sidecar$$"; then \
		echo "✗ Kerberos sidecar not running"; \
		echo "Start it with: make start"; \
		exit 1; \
	fi
	@echo "Ticket information:"
	@docker exec kerberos-sidecar klist 2>/dev/null || echo "✗ No ticket available"

logs: ## Show service logs
	@$(DOCKER_COMPOSE) logs --tail=50 --follow

clean: ## Remove Kerberos container and volume
	@echo "⚠️  This will remove the Kerberos container and ticket cache"
	@echo ""
	@read -p "Are you sure? [y/N]: " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "Cancelled"; \
		exit 1; \
	fi
	@echo "Removing Kerberos sidecar..."
	@$(DOCKER_COMPOSE) down -v
	@echo "✓ Kerberos sidecar removed (container and volume deleted)"
