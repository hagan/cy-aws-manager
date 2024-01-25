# Makefile
include config.mk
export

APPSTREAM_LAMBDA_API := "$(APPSTREAM_LAMBDA_ROOT_URL)$(APPSTREAM_API)"
APPSTREAM_LAMBDA_API := $(shell echo $(APPSTREAM_LAMBDA_API) | sed "s/'//g")
# Define the Dockerfile name
DOCKERFILE := $(DOCKER_DIR)/Dockerfile

# Default target
.PHONY: all
all: build

.PHONY: compile
compile:
	@echo "Building flask wheel... $(NVM_DIR)"
	cd $(FLASK_DIR) && \
	[ -s "$(NVM_DIR)/nvm.sh" ] && \. "$(NVM_DIR)/nvm.sh" && \
	nvm use stable && \
	npm install && \
	NODE_ENV=production ./node_modules/.bin/webpack --progress --color --optimization-minimize && \
	poetry run flask digest compile && \
	touch ./awsmgr/__init__.py && \
	ls -lhtp ./dist/*.whl | head -n1 | awk '{print $$9, $$5}'

.PHONY: build
build:
	@echo "Building Docker image..."
	docker image build \
		--progress=plain \
		-f $(DOCKERFILE) \
		-t $(DOCKER_IMAGE):$(DOCKER_TAG) \
		--no-cache \
		--build-arg IMAGE_NAME=$(DOCKER_IMAGE) \
		--build-arg TAG=$(DOCKER_TAG) \
		--build-arg DOCKER_DIR=$(DOCKER_DIR) \
		$(CONTEXT)

.PHONY: start
start:
	@echo "Starting Docker container..."
	docker run \
		-p 80:80 \
		-p 8080:8080 \
		-p 2022:22 \
		-ti --init --rm \
		--name $(DOCKER_IMAGE) \
		$(DOCKER_IMAGE):$(DOCKER_TAG)


# docker exec --privileged -it $(IMAGE_NAME) /bin/bash
.PHONY: shell
shell:
	@echo "Running Docker $(DOCKER_IMAGE):$(DOCKER_TAG)  bash shell"
	docker exec -it $(DOCKER_IMAGE) /bin/bash

.PHONY: clean
clean:
	@echo "Cleaning up..."
	docker rmi $$(docker images -f "dangling=true" -q) 2> /dev/null || true
	docker rm -f $(DOCKER_IMAGE)
	@echo "Clean up complete!"

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
	docker exec -it appstream /bin/bash

.PHONY: harbor-shell-ni
harbor-shell-ni:
	@echo "Starting shell without instance"
	docker run --rm -it --entrypoint /bin/bash appstream

.PHONY: harbor-login
harbor-login:
	docker login harbor.cyverse.org
