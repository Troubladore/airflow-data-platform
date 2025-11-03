# SQLModel Runner Makefile

.PHONY: help build test clean push shell

# Default image name
IMAGE_NAME ?= sqlmodel-runner
IMAGE_TAG ?= latest
# Use GitHub repository variable if available, otherwise use default
GITHUB_REPOSITORY ?= troubladore/airflow-data-platform
REGISTRY ?= ghcr.io/$(shell echo $(GITHUB_REPOSITORY) | tr '[:upper:]' '[:lower:]')

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

build: ## Build the SQLModel runner Docker image
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .
	docker tag $(IMAGE_NAME):$(IMAGE_TAG) $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

test: ## Run tests for the SQLModel runner
	@echo "Running import tests..."
	python tests/test_imports.py || true
	@echo ""
	@echo "Running integration tests..."
	python tests/test_runner_integration.py || true
	@echo ""
	@echo "Running mounted code tests..."
	python tests/test_mounted_code.py || true

test-docker: build ## Test the Docker image
	@echo "Testing Docker image..."
	docker run --rm $(IMAGE_NAME):$(IMAGE_TAG) python -c "import sqlmodel; import pandas; print('All imports successful!')"

clean: ## Clean up Docker images
	docker rmi $(IMAGE_NAME):$(IMAGE_TAG) || true
	docker rmi $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG) || true

push: build ## Push image to registry (requires authentication)
	docker push $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

shell: build ## Run interactive shell in the container
	docker run --rm -it $(IMAGE_NAME):$(IMAGE_TAG) /bin/bash

install-dev: ## Install development dependencies locally
	pip install -r requirements.txt
	pip install pytest pytest-cov black isort mypy

format: ## Format code with black and isort
	black tests/
	isort tests/

lint: ## Run linting checks
	black --check tests/
	isort --check tests/
	mypy tests/ || true