# Pagila Sample Database Service
# ================================
# Provides the Pagila sample database for development and testing
#
# This service depends on platform-infrastructure (PostgreSQL)

.PHONY: help build-pagila-test test-connection

# Load configuration from central platform-bootstrap/.env
-include ../platform-bootstrap/.env
export

# Default target
help: ## Show this help message
	@echo "Pagila Sample Database Service"
	@echo "==============================="
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""

build-pagila-test: ## Build pagila-test container (supports prebuilt and build-from-base modes)
	@source ../platform-bootstrap/.env 2>/dev/null || true && \
	if [ "$${PAGILA_TEST_PREBUILT}" = "true" ]; then \
		echo "Pulling prebuilt pagila-test image: $${IMAGE_PAGILA_TEST}" && \
		if ! docker pull $${IMAGE_PAGILA_TEST} 2>&1; then \
			echo "Pull failed, checking if image exists locally..." >&2; \
		fi && \
		if ! docker image inspect $${IMAGE_PAGILA_TEST} >/dev/null 2>&1; then \
			echo "Error: Prebuilt image $${IMAGE_PAGILA_TEST} not found locally or in registry" >&2 && exit 1; \
		fi && \
		docker tag $${IMAGE_PAGILA_TEST} platform/pagila-test:latest; \
	else \
		echo "Building pagila-test from base: $${IMAGE_PAGILA_TEST:-alpine:latest}" && \
		docker build \
		  -f test-containers/pagila-test/Dockerfile \
		  --build-arg BASE_IMAGE=$${IMAGE_PAGILA_TEST:-alpine:latest} \
		  -t platform/pagila-test:latest \
		  test-containers/pagila-test/; \
	fi

test-connection: ## Test connection to Pagila database
	@echo "Testing Pagila database connection..."
	@docker run --rm --network platform_network platform/pagila-test:latest \
		psql -h pagila-postgres -U postgres -d pagila -c "SELECT 'Connected to Pagila!' as status;" 2>/dev/null || \
		(echo "Failed to connect to Pagila database" && exit 1)
	@echo "✓ Pagila database connection successful"