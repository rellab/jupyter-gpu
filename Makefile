SHELL := /bin/bash

# ---------------------------------------------------------
# Paths
# ---------------------------------------------------------
ROOT_DIR := $(CURDIR)
DOCKERFILE ?= $(ROOT_DIR)/Dockerfile

# ---------------------------------------------------------
# Environment (.env)
# ---------------------------------------------------------
ifneq (,$(wildcard .env))
include .env
endif

# ---------------------------------------------------------
# Docker / Build Configuration
# ---------------------------------------------------------
DOCKER ?= docker
IMAGE_NAME ?= jupyter-gpu
IMAGE_TAG ?= latest
IMAGE_ORGANIZATION ?= rellab
DOCKER_REGISTRY ?= ghcr.io
DOCKER_USERNAME ?= $(GITHUB_USER)
DOCKER_TOKEN ?= $(GITHUB_TOKEN)
PLATFORM ?= linux/amd64
BUILDX_BUILDER ?= multiarch-builder

# Fallback to defaults when variables are present but empty.
IMAGE_NAME := $(or $(strip $(IMAGE_NAME)),jupyter-gpu)
IMAGE_ORGANIZATION := $(or $(strip $(IMAGE_ORGANIZATION)),rellab)
DOCKER_REGISTRY := $(or $(strip $(DOCKER_REGISTRY)),ghcr.io)
DOCKER_USERNAME := $(or $(strip $(DOCKER_USERNAME)),$(strip $(GITHUB_USER)))
DOCKER_TOKEN := $(or $(strip $(DOCKER_TOKEN)),$(strip $(GITHUB_TOKEN)))

# CUDA versions support
CUDA_VERSIONS := 12.2 11.8
CUDA_VERSION ?= 12.2

# Docker image paths
DOCKERFILE_CUDA_12.2 ?= $(ROOT_DIR)/Dockerfile.cuda12.2
DOCKERFILE_CUDA_11.8 ?= $(ROOT_DIR)/Dockerfile.cuda11.8

# Push image with CUDA version tag (no prefix)
PUSH_IMAGE ?= $(DOCKER_REGISTRY)/$(IMAGE_ORGANIZATION)/$(IMAGE_NAME):cuda$(CUDA_VERSION)

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  build              Build Docker image locally (amd64)"
	@echo "  buildx             Build with buildx and load to local Docker (amd64)"
	@echo "  push               Build with buildx and push to registry (amd64)"
	@echo "  push-all           Build and push both CUDA 12.2 and 11.8"
	@echo "  run                Run the container locally"
	@echo "  clean              Cleanup build cache"
	@echo ""
	@echo "Configuration (from .env or environment):"
	@echo "  GITHUB_USER        GitHub username for authentication (from .env)"
	@echo "  GITHUB_TOKEN       GitHub token for authentication (from .env)"
	@echo "  IMAGE_ORGANIZATION Organization name (default: rellab, override in .env or env)"
	@echo "  DOCKER_REGISTRY    Docker registry (default: ghcr.io)"
	@echo "  IMAGE_NAME         Image name (default: jupyter-gpu)"
	@echo "  IMAGE_TAG          Image tag (default: latest)"
	@echo "  CUDA_VERSION       CUDA version (default: 12.2, options: 12.2 | 11.8)"
	@echo ""
	@echo "Examples:"
	@echo "  make build CUDA_VERSION=12.2"
	@echo "  make buildx CUDA_VERSION=11.8"
	@echo "  make push CUDA_VERSION=12.2"
	@echo "  make push-all"
	@echo "  make push IMAGE_ORGANIZATION=rellab CUDA_VERSION=12.2"

# ---------------------------------------------------------
# Build and Push
# ---------------------------------------------------------

.PHONY: _buildx-bootstrap
_buildx-bootstrap:
	@if ! $(DOCKER) buildx inspect $(BUILDX_BUILDER) >/dev/null 2>&1; then \
		$(DOCKER) buildx create --name $(BUILDX_BUILDER) --use; \
	else \
		$(DOCKER) buildx use $(BUILDX_BUILDER); \
	fi
	$(DOCKER) buildx inspect --bootstrap

.PHONY: _login
_login:
	@if [ -z "$(DOCKER_USERNAME)" ] || [ -z "$(DOCKER_TOKEN)" ]; then \
		echo "Error: DOCKER_USERNAME and DOCKER_TOKEN must be set"; \
		exit 1; \
	fi
	echo "$(DOCKER_TOKEN)" | $(DOCKER) login $(DOCKER_REGISTRY) -u $(DOCKER_USERNAME) --password-stdin

.PHONY: _get-dockerfile
_get-dockerfile:
	@if [ "$(CUDA_VERSION)" = "12.2" ]; then \
		echo $(DOCKERFILE_CUDA_12.2); \
	elif [ "$(CUDA_VERSION)" = "11.8" ]; then \
		echo $(DOCKERFILE_CUDA_11.8); \
	else \
		echo "Error: Unsupported CUDA_VERSION=$(CUDA_VERSION). Supported: 12.2 11.8"; \
		exit 1; \
	fi

.PHONY: build
build:
	$(DOCKER) build \
		-t $(IMAGE_NAME):cuda$(CUDA_VERSION) \
		-f $(shell $(MAKE) -s _get-dockerfile CUDA_VERSION=$(CUDA_VERSION)) \
		.

.PHONY: buildx
buildx: _buildx-bootstrap
	$(DOCKER) buildx build \
		--platform $(PLATFORM) \
		-f $(shell $(MAKE) -s _get-dockerfile CUDA_VERSION=$(CUDA_VERSION)) \
		-t $(IMAGE_NAME):cuda$(CUDA_VERSION) \
		--load \
		.

.PHONY: push
push: _buildx-bootstrap _login
	$(DOCKER) buildx build \
		--platform $(PLATFORM) \
		-f $(shell $(MAKE) -s _get-dockerfile CUDA_VERSION=$(CUDA_VERSION)) \
		-t $(PUSH_IMAGE) \
		--push \
		.

.PHONY: push-cuda12.2
push-cuda12.2: 
	$(MAKE) push CUDA_VERSION=12.2

.PHONY: push-cuda11.8
push-cuda11.8:
	$(MAKE) push CUDA_VERSION=11.8

.PHONY: push-all
push-all: push-cuda12.2 push-cuda11.8
	@echo "Successfully pushed both CUDA 12.2 and 11.8 images"

.PHONY: run
run:
	$(DOCKER) run --rm -it \
		-p 8888:8888 \
		$(IMAGE_NAME):cuda$(CUDA_VERSION)

# ---------------------------------------------------------
# Cleanup
# ---------------------------------------------------------

.PHONY: clean
clean:
	$(DOCKER) buildx prune -f