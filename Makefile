# Makefile

include .env.docker
export

APPSTREAM_LAMBDA_API := "$(APPSTREAM_LAMBDA_ROOT_URL)$(APPSTREAM_API)"
APPSTREAM_LAMBDA_API := $(shell echo $(APPSTREAM_LAMBDA_API) | sed "s/'//g")
# Define the Dockerfile name
DOCKERFILE := $(DOCKER_DIR)/Dockerfile

# Default target
.PHONY: all
all: build



# pull/push/login to harbor!
.PHONY: harbor-pull
harbor-pull:
	@echo "Pulling package from harbor registry"
	docker pull harbor.cyverse.org/vice/$(IMAGE_NAME):$(TAG)

.PHONY: harbor-start
harbor-start:
	@echo "Running vice/$(IMAGE_NAME):$(TAG) image from harbor"
	docker run \
		-p 80:80 \
		-p 8080:8080 \
		-ti --init --rm \
		--name $(IMAGE_NAME) \
		-e BEARER_TOKEN=$(BEARER_TOKEN) \
		-e APPSTREAM_STREAMING_URL=$(APPSTREAM_STREAMING_URL) \
		harbor.cyverse.org/vice/$(IMAGE_NAME):$(TAG)

.PHONY: harbor-shell
harbor-shell:
	@echo "starting shell from running instance"
	docker exec -it $(IMAGE_NAME) /bin/bash

.PHONY: harbor-login
harbor-login:
	docker login harbor.cyverse.org
