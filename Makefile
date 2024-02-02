# Makefile
include config.mk
export

BUILDX_NAME ?= mybuilder
DOCKERHUB_USER ?= hagan
PYNODE_VERSION ?= alpine3.19v2
PULUMI_VERSION ?= v0.0.1
AWSMGR_VERSION ?= v0.0.2
VICE_VERSION ?= v0.0.1
PLATFORMS := linux/amd64,linux/arm64

PYNODE_DKR_DIR ?= ./src/vice/dockerhub/pynode/latest
PULUMI_DKR_DIR ?= ./src/vice/dockerhub/pulumi/latest
AWSMGR_DKR_DIR ?= ./src/vice/dockerhub/awsmgr/latest
VICE_DKR_DIR ?= ./src/vice/latest


APPSTREAM_LAMBDA_API := "$(APPSTREAM_LAMBDA_ROOT_URL)$(APPSTREAM_API)"
APPSTREAM_LAMBDA_API := $(shell echo $(APPSTREAM_LAMBDA_API) | sed "s/'//g")
# Define the Dockerfile name
DOCKERFILE := $(DOCKER_DIR)/Dockerfile

# No files are created
.PHONY: all build-pynode-image push-pynode-image shell-pynode-image \
build-pulumi-image push-pulumi-image shell-pulumi-image \
build-awsmgr-image push-awsmgr-image shell-awsmgr-image \
build-vice-image push-vice-image shell-vice-image \
compile build start shell clean harbor-pull harbor-start \
harbor-shell harbor-shell-ni harbor-login

all: build

build-pynode-image:
	@echo "Building pynode $(PYNODE_VERSION) image"
	cd $(PYNODE_DKR_DIR); \
	docker buildx use $(BUILDX_NAME); \
	docker buildx build \
	  --label pynode \
	  --platform $(PLATFORMS) \
	  --tag $(DOCKERHUB_USER)/pynode:$(PYNODE_VERSION) \
	  --tag $(DOCKERHUB_USER)/pynode:latest .

push-pynode-image:
	@echo "Pushing pynode $(DOCKERHUB_USER)/pynode:latest to hub.docker.com"
	cd $(PYNODE_DKR_DIR); \
	docker push $(DOCKERHUB_USER)/pynode:$(PYNODE_VERSION); \
	docker push $(DOCKERHUB_USER)/pynode:latest

shell-pynode-image:
	@echo "Running pynode $(DOCKERHUB_USER)/pynode:latest"
	cd $(PYNODE_DKR_DIR); \
	docker run --rm -it hagan/pynode:latest /bin/sh

build-pulumi-image:
	@echo "Building pulumi $(PULUMI_VERSION) image"
	cd $(PULUMI_DKR_DIR); \
	docker buildx use $(BUILDX_NAME); \
	docker buildx build \
	  --label pulumi \
	  --platform $(PLATFORMS) \
	  --build-arg PULUMI_PARENT_IMAGE=hagan/pynode \
      --build-arg PULUMI_PARENT_TAG=$(PYNODE_VERSION) \
	  --tag $(DOCKERHUB_USER)/pulumi:$(PULUMI_VERSION) \
	  --tag $(DOCKERHUB_USER)/pulumi:latest .

push-pulumi-image:
	@echo "Pushing pulumi $(DOCKERHUB_USER)/pulumi:latest to hub.docker.com"
	cd $(PULUMI_DKR_DIR); \
	docker push $(DOCKERHUB_USER)/pulumi:$(PULUMI_VERSION); \
	docker push $(DOCKERHUB_USER)/pulumi:latest

shell-pulumi-image:
	@echo "Running pulumi $(DOCKERHUB_USER)/pulumi:latest"
	cd $(PULUMI_DKR_DIR); \
	docker run --rm -it hagan/pulumi:latest /bin/sh

# --load won't work with multiplatform
build-awsmgr-image:
	@echo "Building awsmgr $(AWSMGR_VERSION) image"
	cd $(AWSMGR_DKR_DIR); \
	docker buildx use $(BUILDX_NAME); \
	docker buildx build \
		--label awsmgr \
		--platform $(PLATFORMS) \
		--build-arg AWSMGR_PARENT_IMAGE=hagan/pulumi \
		--build-arg AWSMGR_PARENT_TAG=$(PULUMI_VERSION) \
		--tag $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_VERSION) \
		--tag $(DOCKERHUB_USER)/awsmgr:latest .

push-awsmgr-image:
	@echo "Pushing awsmgr $(DOCKERHUB_USER)/awsmgr:latest to hub.docker.com"
	cd $(AWSMGR_DKR_DIR); \
	docker push $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_VERSION); \
	docker push $(DOCKERHUB_USER)/awsmgr:latest

shell-awsmgr-image:
	@echo "Running awsmgr $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_VERSION)"
	cd $(AWSMGR_DKR_DIR); \
	docker run --rm -it hagan/awsmgr:$(AWSMGR_VERSION) /bin/sh

build-vice-image:
	@echo "Building viceawsmg $(VICE_VERSION) image"
	cd $(VICE_DKR_DIR); \
	docker buildx use $(BUILDX_NAME); \
	docker buildx build \
		--label awsmgr \
		--platform $(PLATFORMS) \
		--build-arg VICE_PARENT_IMAGE=hagan/awsmgr \
		--build-arg VICE_PARENT_TAG=$(AWSMGR_VERSION) \
		--tag $(DOCKERHUB_USER)/viceawsmgr:$(VICE_VERSION) \
		--tag $(DOCKERHUB_USER)/viceawsmgr:latest .

push-vice-image:
	@echo "Pushing viceawsmgr $(DOCKERHUB_USER)/viceawsmgr:latest to hub.docker.com"
	cd $(VICE_DKR_DIR); \
	docker push $(DOCKERHUB_USER)/viceawsmgr:$(VICE_VERSION); \
	docker push $(DOCKERHUB_USER)/viceawsmgr:latest

shell-vice-image:
	@echo "Running viceawsmgr $(DOCKERHUB_USER)/viceawsmgr:$(VICE_VERSION)"
	cd $(VICE_DKR_DIR); \
	docker run --rm -it hagan/viceawsmgr:$(VICE_VERSION) /bin/sh

compile:
	@echo "Building flask wheel... $(NVM_DIR)"
	cd $(FLASK_DIR) && \
	[ -s "$(NVM_DIR)/nvm.sh" ] && \. "$(NVM_DIR)/nvm.sh" && \
	nvm use stable && \
	npm install && \
	NODE_ENV=production ./node_modules/.bin/webpack --progress --color --optimization-minimize && \
	poetry run flask digest compile && \
	touch ./awsmgr/__init__.py && \
	poetry build && \
	ls -lhtp ./dist/*.whl | head -n1 | awk '{print $$9, $$5}'


build:
	@echo "Building Docker image..."
	docker pull $(SRC_DOCKER_IMAGE):$(SRC_DOCKER_VER)
	docker image build \
		--progress=plain \
		-f $(DOCKERFILE) \
		-t $(DOCKER_IMAGE):$(DOCKER_TAG) \
		--no-cache \
		--build-arg SRC_DOCKER_IMAGE=$(SRC_DOCKER_IMAGE) \
		--build-arg SRC_DOCKER_VER=$(SRC_DOCKER_VER) \
		--build-arg IMAGE_NAME=$(DOCKER_IMAGE) \
		--build-arg TAG=$(DOCKER_TAG) \
		--build-arg DOCKER_DIR=$(DOCKER_DIR) \
		$(CONTEXT)

#  		--env "NODE_SOCK=/tmp/node-nextjs.socket"

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

shell:
	@echo "Running Docker $(DOCKER_IMAGE):$(DOCKER_TAG)  bash shell"
	docker exec -it $(DOCKER_IMAGE) /bin/sh


clean:
	@echo "Cleaning up..."
	docker rmi $$(docker images -f "dangling=true" -q) 2> /dev/null || true
	docker rm -f $(DOCKER_IMAGE)
	@echo "Clean up complete!"

## issue -> docker pull harbor.cyverse.org/vice/$(DOCKER_IMAGE):$(DOCKER_TAG)
## Currently using old appstreamer on harbor, need to move to amazonmgr
# pull/push/login to harbor!

harbor-pull:
	@echo "Pulling package from harbor registry"
	# -docker rmi harbor.cyverse.org/vice/appstream:latest
	docker pull harbor.cyverse.org/vice/appstream:latest

## issue -> @echo "Running vice/$(IMAGE_NAME):$(TAG) image from harbor"
## -e BEARER_TOKEN=$(BEARER_TOKEN)
## -e APPSTREAM_STREAMING_URL=$(APPSTREAM_STREAMING_URL)
## issue -> harbor.cyverse.org/vice/$(IMAGE_NAME):$(TAG)

harbor-start:
	@echo "Running vice/appstream:latest image from harbor"
	docker run \
		-p 80:80 \
		-p 8080:8080 \
		-ti --init --rm \
		--name appstream \
		harbor.cyverse.org/vice/appstream:latest

## issue -> docker exec -it $(IMAGE_NAME) /bin/bash


harbor-shell:
	@echo "Starting shell from running instance"
	docker exec -it appstream /bin/bash


harbor-shell-ni:
	@echo "Starting shell without instance"
	docker run --rm -it --entrypoint /bin/bash appstream


harbor-login:
	docker login harbor.cyverse.org
