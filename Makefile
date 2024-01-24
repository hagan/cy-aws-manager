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


## issue -> docker pull harbor.cyverse.org/vice/$(DOCKER_IMAGE):$(DOCKER_TAG)
## Currently using old appstreamer on harbor, need to move to amazonmgr
# pull/push/login to harbor!
.PHONY: harbor-pull
harbor-pull:
	@echo "Pulling package from harbor registry"
	# -docker rmi harbor.cyverse.org/vice/appstream:latest
	docker pull harbor.cyverse.org/vice/appstream:latest

## issue -> @echo "Running vice/$(IMAGE_NAME):$(TAG) image from harbor"
## -e BEARER_TOKEN=$(BEARER_TOKEN)
## -e APPSTREAM_STREAMING_URL=$(APPSTREAM_STREAMING_URL)
## issue -> harbor.cyverse.org/vice/$(IMAGE_NAME):$(TAG)

.PHONY: harbor-start
harbor-start:
	@echo "Running vice/appstream:latest image from harbor"
	docker run \
		-p 80:80 \
		-p 8080:8080 \
		-ti --init --rm \
		--name appstream \
		harbor.cyverse.org/vice/appstream:latest

## issue -> docker exec -it $(IMAGE_NAME) /bin/bash

.PHONY: harbor-shell
harbor-shell:
	@echo "Starting shell from running instance"
	docker run --rm -it harbor.cyverse.org/vice/appstream:latest /bin/bash

.PHONY: harbor-shell-ni
harbor-shell-ni:
	@echo "Starting shell without instance"
	docker run --rm -it --entrypoint /bin/bash harbor.cyverse.org/vice/appstream:latest

.PHONY: harbor-login
harbor-login:
	docker login harbor.cyverse.org
