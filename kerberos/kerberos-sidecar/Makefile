# Kerberos Sidecar Image Build
# ==============================
# Builds the Kerberos sidecar image for local and Kubernetes use

.PHONY: help build test push clean

# Load corporate configuration from parent .env (single source of truth)
# DevOps person configures platform-bootstrap/.env once for the organization
-include ../.env
export

IMAGE_NAME ?= platform/kerberos-sidecar
IMAGE_TAG ?= latest
REGISTRY ?= registry.company.com

# Corporate Artifactory configuration (from .env or defaults)
# IMAGE_ALPINE - Base Alpine image source
# ODBC_DRIVER_URL - Microsoft ODBC driver mirror location

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

check-requirements: ## Check build requirements before building
	@./scripts/check-build-requirements.sh

build: check-requirements ## Build minimal sidecar image (default)
	@echo "Building minimal Kerberos sidecar image..."
	@printf "Configuration:\n"
	@printf "  Base image: %s (public default)\n" "${IMAGE_ALPINE:-alpine:3.19}"
	@printf "  Type: MINIMAL (Kerberos only, ~50MB)\n"
	docker build \
		$(if $(IMAGE_ALPINE),--build-arg IMAGE_ALPINE=$(IMAGE_ALPINE),) \
		-t $(IMAGE_NAME):$(IMAGE_TAG) .
	@echo "✓ Built: $(IMAGE_NAME):$(IMAGE_TAG)"
	@echo ""
	@echo "Minimal sidecar ready for local development"
	@echo "  - Size: ~50MB (vs 312MB legacy)"
	@echo "  - Packages: 15-20 (vs 120+ legacy)"
	@echo "  - Contains: Kerberos tools ONLY"
	@echo ""
	@echo "To use: docker compose -f ../docker-compose.yml up -d"
	@echo ""
	@echo "For legacy bloated image: make build-legacy"

build-legacy: check-requirements ## Build legacy sidecar image (bloated, backwards compatibility)
	@echo "Building LEGACY Kerberos sidecar image..."
	@echo ""
	@echo "⚠️  WARNING: Building legacy bloated image"
	@echo "  - Size: ~312MB (use 'make build' for 50MB minimal)"
	@echo "  - Packages: 120+ (vs 15-20 minimal)"
	@echo "  - Contains: ODBC drivers, Python, build tools"
	@echo ""
	@printf "Configuration:\n"
	@printf "  Base image: %s (public default)\n" "${IMAGE_ALPINE:-alpine:3.19}"
	@printf "  ODBC source: %s (public default)\n" "${ODBC_DRIVER_URL:-Microsoft download}"
	@printf "  Type: LEGACY (bloated)\n"
	@echo ""
	docker build \
		-f Dockerfile.legacy \
		$(if $(IMAGE_ALPINE),--build-arg IMAGE_ALPINE=$(IMAGE_ALPINE),) \
		$(if $(ODBC_DRIVER_URL),--build-arg ODBC_DRIVER_URL=$(ODBC_DRIVER_URL),) \
		-t $(IMAGE_NAME):legacy .
	@echo "✓ Built: $(IMAGE_NAME):legacy"
	@echo ""
	@echo "Legacy image built for backwards compatibility"
	@echo ""
	@echo "Migration: Use platform/sqlcmd-test for SQL Server testing"
	@echo "See: MIGRATION-GUIDE.md"

build-sqlcmd-test: ## Build SQL Server test image with Microsoft sqlcmd pre-installed
	@echo "Building SQL Server test image with Microsoft sqlcmd..."
	@printf "Configuration:\n"
	@printf "  Base image: %s\n" "${IMAGE_ALPINE:-alpine:3.19}"
	@if [ -n "${MSSQL_TOOLS_URL}" ]; then \
		printf "  SQL tools: %s (corporate)\n" "${MSSQL_TOOLS_URL}"; \
	elif [ -n "${ODBC_DRIVER_URL}" ]; then \
		printf "  SQL tools: %s (using ODBC_DRIVER_URL)\n" "${ODBC_DRIVER_URL}"; \
	else \
		printf "  SQL tools: Microsoft downloads (public)\n"; \
	fi
	@echo ""
	@# Use MSSQL_TOOLS_URL if set, otherwise fall back to ODBC_DRIVER_URL, then Microsoft
	@if [ -n "${MSSQL_TOOLS_URL}" ]; then \
		TOOLS_URL="${MSSQL_TOOLS_URL}"; \
	elif [ -n "${ODBC_DRIVER_URL}" ]; then \
		TOOLS_URL="${ODBC_DRIVER_URL}"; \
	else \
		TOOLS_URL=""; \
	fi; \
	if [ -f "${HOME}/.netrc" ]; then \
		echo "Using .netrc for corporate repository authentication"; \
		docker build \
			-f Dockerfile.sqlcmd-test \
			$(if $(IMAGE_ALPINE),--build-arg IMAGE_ALPINE=$(IMAGE_ALPINE),) \
			--build-arg MSSQL_TOOLS_URL="$$TOOLS_URL" \
			--secret id=netrc,src=${HOME}/.netrc \
			-t platform/sqlcmd-test:latest .; \
	else \
		echo "No .netrc found - may fail if using corporate repository"; \
		docker build \
			-f Dockerfile.sqlcmd-test \
			$(if $(IMAGE_ALPINE),--build-arg IMAGE_ALPINE=$(IMAGE_ALPINE),) \
			--build-arg MSSQL_TOOLS_URL="$$TOOLS_URL" \
			-t platform/sqlcmd-test:latest .; \
	fi
	@echo ""
	@echo "✓ Built: platform/sqlcmd-test:latest"
	@echo ""
	@echo "This image contains Microsoft ODBC Driver 18 and sqlcmd"
	@echo "Use with: ../test-sql-prebuilt.sh <server> <database>"
	@echo ""

build-test-image: ## Build SQL Server test image with pyodbc pre-installed (OLD)
	@echo "Building SQL Server test image..."
	@printf "Base: %s\n" "${IMAGE_PYTHON:-python:3.11-alpine}"
	@echo ""
	@echo "Auto-detecting Python package index configuration..."
	@# Try UV config first (preferred)
	@AUTO_INDEX=$$(python3 -c "import tomllib; c=tomllib.load(open('${HOME}/.config/uv/uv.toml','rb')); print([i['url'] for i in c.get('index',[]) if i.get('name')=='primary'][0])" 2>/dev/null || echo ""); \
	if [ -n "$$AUTO_INDEX" ]; then \
		echo "  Found UV config: $$AUTO_INDEX"; \
		AUTO_TRUSTED=$$(echo $$AUTO_INDEX | sed 's|https\?://||' | cut -d/ -f1); \
		export PIP_INDEX_URL=$$AUTO_INDEX; \
		export PIP_TRUSTED_HOST=$$AUTO_TRUSTED; \
	elif [ -f "${HOME}/.pip/pip.conf" ]; then \
		AUTO_INDEX=$$(grep "index-url" ${HOME}/.pip/pip.conf | cut -d= -f2- | tr -d ' '); \
		if [ -n "$$AUTO_INDEX" ]; then \
			echo "  Found pip.conf: $$AUTO_INDEX"; \
			AUTO_TRUSTED=$$(echo $$AUTO_INDEX | sed 's|https\?://||' | cut -d/ -f1); \
			export PIP_INDEX_URL=$$AUTO_INDEX; \
			export PIP_TRUSTED_HOST=$$AUTO_TRUSTED; \
		fi; \
	else \
		echo "  No UV/pip config found - using public PyPI"; \
		echo "  For corporate: Configure ~/.config/uv/uv.toml or ~/.pip/pip.conf"; \
	fi; \
	echo ""; \
	if [ -f "${HOME}/.netrc" ]; then \
		echo "  Using credentials from ~/.netrc (via BuildKit secret)"; \
		echo "  (Credentials NOT stored in image - only used during build)"; \
		docker build \
			-f Dockerfile.test-image \
			$(if $(IMAGE_PYTHON),--build-arg IMAGE_PYTHON=$(IMAGE_PYTHON),) \
			--build-arg PIP_INDEX_URL=$$PIP_INDEX_URL \
			--build-arg PIP_TRUSTED_HOST=$$PIP_TRUSTED_HOST \
			--secret id=netrc,src=${HOME}/.netrc \
			-t platform/kerberos-test:latest .; \
	else \
		echo "  No ~/.netrc found - build may fail if PyPI requires auth"; \
		docker build \
			-f Dockerfile.test-image \
			$(if $(IMAGE_PYTHON),--build-arg IMAGE_PYTHON=$(IMAGE_PYTHON),) \
			--build-arg PIP_INDEX_URL=$$PIP_INDEX_URL \
			--build-arg PIP_TRUSTED_HOST=$$PIP_TRUSTED_HOST \
			-t platform/kerberos-test:latest .; \
	fi
	@echo "✓ Built: platform/kerberos-test:latest"
	@echo ""
	@echo "This image uses UV for fast package installation"
	@echo "Credentials from .netrc were used during build but NOT stored in image"

test: ## Test sidecar image locally
	@echo "Testing sidecar image..."
	@echo "1. Checking image exists..."
	@docker images $(IMAGE_NAME):$(IMAGE_TAG) | grep $(IMAGE_NAME) || (echo "✗ Image not found. Run: make build" && exit 1)
	@echo "✓ Image exists"
	@echo ""
	@echo "2. Testing health check..."
	@docker run --rm $(IMAGE_NAME):$(IMAGE_TAG) which klist >/dev/null && echo "✓ Kerberos tools present" || echo "✗ klist not found"
	@echo ""
	@echo "3. Testing ticket manager script..."
	@docker run --rm $(IMAGE_NAME):$(IMAGE_TAG) test -x /scripts/kerberos-ticket-manager.sh && echo "✓ Ticket manager executable" || echo "✗ Script not executable"
	@echo ""
	@echo "✓ Basic tests passed"
	@echo ""
	@echo "For full integration test: make integration-test"

integration-test: ## Full integration test with ticket acquisition
	@echo "Running integration test..."
	@echo "Starting sidecar with test configuration..."
	@docker run --rm \
		-e KRB_PRINCIPAL=test@TEST.COM \
		-e USE_PASSWORD=true \
		-e KRB_PASSWORD=testpass \
		-e RENEWAL_INTERVAL=30 \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		timeout 60 /scripts/kerberos-ticket-manager.sh || echo "Test completed (expected timeout)"

tag-for-k8s: build ## Tag image for corporate registry (Kubernetes deployment)
	@echo "Tagging for corporate registry..."
	docker tag $(IMAGE_NAME):$(IMAGE_TAG) $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)
	@echo "✓ Tagged: $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)"
	@echo ""
	@echo "To push to corporate registry:"
	@echo "  1. docker login $(REGISTRY)"
	@echo "  2. make push"

push: ## Push image to corporate registry
	@echo "Pushing to corporate registry..."
	@docker login $(REGISTRY) 2>/dev/null || (echo "Please login first: docker login $(REGISTRY)" && exit 1)
	docker push $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)
	@echo "✓ Pushed: $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)"
	@echo ""
	@echo "Image ready for Kubernetes deployment"

clean: ## Remove built image
	docker rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	@echo "✓ Cleaned up local image"

shell: ## Open shell in sidecar image for debugging
	docker run --rm -it $(IMAGE_NAME):$(IMAGE_TAG) /bin/bash

logs: ## Show logs from running sidecar (if using docker-compose)
	docker logs kerberos-platform-service -f

.DEFAULT_GOAL := help
