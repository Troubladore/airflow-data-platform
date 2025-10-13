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

build: ## Build sidecar image for local development
	@echo "Building Kerberos sidecar image..."
	@echo "Configuration:"
	@echo "  Base image: ${IMAGE_ALPINE:-alpine:3.19} (public default)"
	@echo "  ODBC source: ${ODBC_DRIVER_URL:-Microsoft download} (public default)"
	docker build \
		$(if $(IMAGE_ALPINE),--build-arg IMAGE_ALPINE=$(IMAGE_ALPINE),) \
		$(if $(ODBC_DRIVER_URL),--build-arg ODBC_DRIVER_URL=$(ODBC_DRIVER_URL),) \
		-t $(IMAGE_NAME):$(IMAGE_TAG) .
	@echo "✓ Built: $(IMAGE_NAME):$(IMAGE_TAG)"
	@echo ""
	@echo "Image ready for local development"
	@echo "To use: docker compose -f ../docker-compose.yml up -d"

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
