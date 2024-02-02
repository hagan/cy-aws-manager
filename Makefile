# Makefile
include config.mk
export

GIT_HASH ?= $(shell git log --format="%h" -n 1)
BUILDX_NAME ?= mybuilder
DOCKERHUB_USER ?= $(whoami)
# Supporing/source Dockerfile images
PYNODE_DKR_DIR ?= ./src/vice/dockerhub/pynode/latest
PULUMI_DKR_DIR ?= ./src/vice/dockerhub/pulumi/latest
AWSMGR_DKR_DIR ?= ./src/vice/dockerhub/awsmgr/latest
# The Dockerfile for our VICE application
VICE_DKR_DIR ?= ./src/vice/latest

PYNODE_LATEST ?= $(shell readlink $(PYNODE_DKR_DIR) | grep -oP '(^.*/)?\K[^/]+(?=/?$$)')
PYNODE_VERSION ?= alpine3.19${PYNODE_LATEST}
PULUMI_LATEST ?= $(shell readlink $(PULUMI_DKR_DIR) | grep -oP '(^.*/)?\K[^/]+(?=/?$$)')
PULUMI_VERSION ?= v$(PULUMI_LATEST)
AWSMGR_LATEST ?= $(shell readlink $(AWSMGR_DKR_DIR) | grep -oP '(^.*/)?\K[^/]+(?=/?$$)')
AWSMGR_VERSION ?= v$(AWSMGR_LATEST)
VICE_LATEST ?= $(shell readlink $(VICE_DKR_DIR) | grep -oP '(^.*/)?\K[^/]+(?=/?$$)')
VICE_VERSION ?= $(VICE_LATEST)
## for apple uncomment 
# PLATFORMS := linux/amd64,linux/arm64
PLATFORMS := linux/amd64
LOCAL_PLATFORM ?= linux/arm64

APPSTREAM_LAMBDA_API := "$(APPSTREAM_LAMBDA_ROOT_URL)$(APPSTREAM_API)"
APPSTREAM_LAMBDA_API := $(shell echo $(APPSTREAM_LAMBDA_API) | sed "s/'//g")
# Define the Dockerfile name
DOCKERFILE := $(DOCKER_DIR)/Dockerfile


ifeq ($(NOCACHE),yes)
CACHEFLAG := --no-cache
else
CACHEFLAG :=
endif

ifeq ($(DOCKERHUB),yes)
PUSHFLAG := --push
else
PUSHFLAG :=
endif

ifeq ($(LOCAL),yes)
LOADFLAG := --load
PLATFORMS := $(LOCAL_PLATFORM)
else
LOADFLAG :=
endif

# No files are created
.PHONY: all show-vars \
build-pynode-image clean-pynode-image push-pynode-image shell-pynode-image \
build-pulumi-image clean-pulumi-image push-pulumi-image shell-pulumi-image \
build-awsmgr-image push-awsmgr-image shell-awsmgr-image \
build-vice-image push-vice-image shell-vice-image \
compile build start shell clean harbor-pull harbor-start \
harbor-shell harbor-shell-ni harbor-login

all: build

show-vars:
	@echo "DOCKERHUB_USER: $(DOCKERHUB_USER)"
	@echo "PYNODE_LATEST: $(PYNODE_LATEST)"
	@echo "PYNODE_VERSION: $(PYNODE_VERSION)"
	@echo "PULUMI_LATEST: $(PULUMI_LATEST)"
	@echo "AWSMGR_LATEST: $(AWSMGR_LATEST)"
	@echo "AWSMGR_VERSION: $(AWSMGR_VERSION)"
	@echo "VICE_LATEST: $(VICE_LATEST)"
	@echo "VICE_VERSION: $(VICE_VERSION)"

## PYNODE
# Build pynode (Python/Node & Golang)
build-pynode-image:
	@echo "Building pynode $(PYNODE_VERSION) image"
	cd $(PYNODE_DKR_DIR); \
	docker buildx use $(BUILDX_NAME); \
	docker buildx build \
		--label pynode \
		--platform $(PLATFORMS) \
		--build-arg PYNODE_PARENT_IMAGE=alpine \
    	--build-arg PYNODE_PARENT_TAG=3.19 \
		$(CACHEFLAG) $(LOADFLAG) \
		--tag $(DOCKERHUB_USER)/pynode:$(PYNODE_VERSION)-$(GIT_HASH) \
		--tag $(DOCKERHUB_USER)/pynode:$(PYNODE_VERSION) \
    	--tag $(DOCKERHUB_USER)/pynode:latest \
		$(PUSHFLAG) .
# Tag pynode
tag-pynode-image:
	@echo "Tag $(DOCKERHUB_USER)/pynode:$(PYNODE_VERSION) as latest"
	docker tag $(DOCKERHUB_USER)/pynode:$(PYNODE_VERSION)-$(GIT_HASH) $(DOCKERHUB_USER)/pynode:$(PYNODE_VERSION)
	docker tag $(DOCKERHUB_USER)/pynode:$(PYNODE_VERSION)-$(GIT_HASH) $(DOCKERHUB_USER)/pynode:latest
# Clean pynode
clean-pynode-image:
	@echo "Cleaning images out for pynode"
	docker rmi $(DOCKERHUB_USER)/pynode:$(PYNODE_VERSION) 2>/dev/null || echo "Image pynode:$(PYNODE_VERSION) has already been removed."
	docker rmi $(DOCKERHUB_USER)/pynode:$(PYNODE_VERSION)-* 2>/dev/null || echo "Image pynode:$(PYNODE_VERSION)-* has already been removed."
	docker rmi $(DOCKERHUB_USER)/pynode:latest 2>/dev/null || echo "Image pynode:latest has already been removed."
	@echo "To complete removal, run: docker images prune -a"
# Push pynode
push-pynode-image:
	@echo "Pushing pynode $(DOCKERHUB_USER)/pynode:latest to hub.docker.com"
	cd $(PYNODE_DKR_DIR); \
	docker push $(DOCKERHUB_USER)/pynode:$(PYNODE_VERSION)-$(GIT_HASH); \
	docker push $(DOCKERHUB_USER)/pynode:$(PYNODE_VERSION); \
	docker push $(DOCKERHUB_USER)/pynode:latest
# Shell pynode
shell-pynode-image:
	@echo "Running pynode $(DOCKERHUB_USER)/pynode:$(PYNODE_VERSION)"
	cd $(PYNODE_DKR_DIR); \
	docker run --rm -it hagan/pynode:latest /bin/sh
## PULUMI
# Build pulumi
build-pulumi-image:
	@echo "Building pulumi $(PULUMI_VERSION) image"
	cd $(PULUMI_DKR_DIR); \
	docker buildx use $(BUILDX_NAME); \
	docker buildx build \
		--label pulumi \
		--platform $(PLATFORMS) \
		--build-arg PULUMI_PARENT_IMAGE=hagan/pynode \
		--build-arg PULUMI_PARENT_TAG=$(PYNODE_VERSION) \
		$(CACHEFLAG) $(LOADFLAG) \
		--tag $(DOCKERHUB_USER)/pulumi:$(PULUMI_VERSION)-$(GIT_HASH) \
		--tag $(DOCKERHUB_USER)/pulumi:$(PULUMI_VERSION) \
		--tag $(DOCKERHUB_USER)/pulumi:latest \
		$(PUSHFLAG) .
# Tag pulumi
tag-pulumi-image:
	@echo "Tag $(DOCKERHUB_USER)/pulumi:$(PULUMI_VERSION) as latest"
	docker tag $(DOCKERHUB_USER)/pulumi:$(PULUMI_VERSION)-$(GIT_HASH) $(DOCKERHUB_USER)/pulumi:latest
	docker tag $(DOCKERHUB_USER)/pulumi:$(PULUMI_VERSION)-$(GIT_HASH) $(DOCKERHUB_USER)/pulumi:$(PULUMI_VERSION)
# Clean pulumi
clean-pulumi-image:
	@echo "Cleaning images out for pulumi"
	docker rmi $(DOCKERHUB_USER)/pulumi:$(PULUMI_VERSION) 2>/dev/null || echo "Image pulumi:$(PULUMI_VERSION) has already been removed."
	docker rmi $(DOCKERHUB_USER)/pulumi:$(PULUMI_VERSION)-* 2>/dev/null || echo "Image pulumi:$(PULUMI_VERSION)-* has already been removed."
	docker rmi $(DOCKERHUB_USER)/pulumi:latest 2>/dev/null || echo "Image pulumi:latest has already been removed."
	@echo "To complete removal, run: docker images prune -a"
# Push pulumi
push-pulumi-image:
	@echo "Pushing pulumi $(DOCKERHUB_USER)/pulumi:latest to hub.docker.com"
	cd $(PULUMI_DKR_DIR); \
	docker push $(DOCKERHUB_USER)/pulumi:$(PULUMI_VERSION)-$(GIT_HASH); \
	docker push $(DOCKERHUB_USER)/pulumi:$(PULUMI_VERSION); \
	docker push $(DOCKERHUB_USER)/pulumi:latest
# shell pulumi
shell-pulumi-image:
	@echo "Running pulumi $(DOCKERHUB_USER)/pulumi:$(PULUMI_VERSION)"
	cd $(PULUMI_DKR_DIR); \
	docker run --rm -it hagan/pulumi:latest /bin/sh
## AWSMGR
# build awsmgr
build-awsmgr-image:
	@echo "Building awsmgr $(AWSMGR_VERSION) image"
	cd $(AWSMGR_DKR_DIR); \
	docker buildx use $(BUILDX_NAME); \
	docker buildx build \
		--label awsmgr \
		--platform $(PLATFORMS) \
		--build-arg AWSMGR_PARENT_IMAGE=hagan/pulumi \
		--build-arg AWSMGR_PARENT_TAG=$(PULUMI_VERSION) \
		$(CACHEFLAG) $(LOADFLAG) \
		--tag $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_VERSION)-$(GIT_HASH) \
		--tag $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_VERSION) \
		--tag $(DOCKERHUB_USER)/awsmgr:latest \
		$(PUSHFLAG) .
# Tag awsmgr
tag-awsmgr-image:
	@echo "Tag $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_VERSION) as latest"
	docker tag $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_VERSION)-$(GIT_HASH) $(DOCKERHUB_USER)/awsmgr:latest
	docker tag $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_VERSION)-$(GIT_HASH) $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_VERSION)
# clean awsmgr
clean-awsmgr-image:
	@echo "Cleaning images out for awsmgr"
	docker rmi $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_VERSION) 2>/dev/null || echo "Image awsmgr:$(AWSMGR_VERSION) has already been removed."
	docker rmi $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_VERSION)-* 2>/dev/null || echo "Image awsmgr:$(AWSMGR_VERSION)-* has already been removed."
	docker rmi $(DOCKERHUB_USER)/awsmgr:latest 2>/dev/null || echo "Image awsmgr:latest has already been removed."
	@echo "To complete removal, run: docker images prune -a"
# push awsmgr
push-awsmgr-image:
	@echo "Pushing awsmgr $(DOCKERHUB_USER)/awsmgr:latest to hub.docker.com"
	cd $(AWSMGR_DKR_DIR); \
	docker push $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_VERSION); \
	docker push $(DOCKERHUB_USER)/awsmgr:latest
# shell awsmgr
shell-awsmgr-image:
	@echo "Running awsmgr $(DOCKERHUB_USER)/awsmgr:latest"
	cd $(AWSMGR_DKR_DIR); \
	docker run --rm -it hagan/awsmgr:latest /bin/sh
## vice
# build vice
build-vice-image:
	@echo "Building viceawsmg $(VICE_VERSION) image"
	docker buildx use $(BUILDX_NAME); \
	docker buildx build \
		-f $(VICE_DKR_DIR)/Dockerfile \
		--label viceawsmgr \
		--platform $(PLATFORMS) \
		--build-arg VICE_PARENT_IMAGE=hagan/awsmgr \
		--build-arg VICE_PARENT_TAG=$(AWSMGR_VERSION) \
		$(CACHEFLAG) $(LOADFLAG) \
		--tag $(DOCKERHUB_USER)/viceawsmgr:$(VICE_VERSION) \
		--tag $(DOCKERHUB_USER)/viceawsmgr:$(VICE_VERSION)-$(GIT_HASH) \
		--tag $(DOCKERHUB_USER)/viceawsmgr:latest \
		$(PUSHFLAG) .

clean-vice-image:
	@echo "Cleaning images out for vice"
	docker rmi $(DOCKERHUB_USER)/viceawsmgr:$(VICE_VERSION) 2>/dev/null || echo "Image viceawsmgr:$(VICE_VERSION) has already been removed."
	docker rmi $(DOCKERHUB_USER)/viceawsmgr:$(VICE_VERSION)-$(GIT_HASH) 2>/dev/null || echo "Image viceawsmgr:$(VICE_VERSION)-$(GIT_HASH) has already been removed."
	docker rmi $(DOCKERHUB_USER)/viceawsmgr:latest 2>/dev/null || echo "Image viceawsmgr:latest has already been removed."
	@echo "To complete removal, run: docker images prune -a"

push-vice-image:
	@echo "Pushing viceawsmgr $(DOCKERHUB_USER)/viceawsmgr:latest to hub.docker.com"
	cd $(VICE_DKR_DIR); \
	docker push $(DOCKERHUB_USER)/viceawsmgr:$(VICE_VERSION); \
	docker push $(DOCKERHUB_USER)/viceawsmgr:latest

shell-vice-image:
	@echo "Running viceawsmgr $(DOCKERHUB_USER)/viceawsmgr:$(VICE_VERSION)"
	cd $(VICE_DKR_DIR); \
	docker ps --filter "name=vice" | grep vice && docker exec -it vice /bin/sh || \
	docker run --name vice --rm -it hagan/viceawsmgr:latest  /bin/sh

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
