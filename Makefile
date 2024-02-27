# Makefile
include config.mk
export

PULUMI_VERSION ?= 3.106.0
GIT_HASH ?= $(shell git log --format="%h" -n 1)
BUILDX_NAME ?= default
DOCKERHUB_USER ?= $(whoami)
# Supporing/source Dockerfile images
LATEST_PYNODE_DKR_DIR ?= ./src/vice/dockerhub/pynode/latest
LATEST_PULUMI_DKR_DIR ?= ./src/vice/dockerhub/pulumi/latest
LATEST_AWSMGR_DKR_DIR ?= ./src/vice/dockerhub/awsmgr/latest
# The Dockerfile for our VICE application
LATEST_VICE_DKR_DIR ?= ./src/vice/latest


# PYNODE_PARENT_IMAGE := debian
# PYNODE_PARENT_TAG := bookworm
PYNODE_PARENT_IMAGE := python
PYNODE_PARENT_TAG := 3.11.7-bookworm

PYNODE_DKR_VERSION ?= $(shell readlink $(LATEST_PYNODE_DKR_DIR) | grep -oP '(^.*/)?\K[^/]+(?=/?$$)')
PYNODE_DKR_DIR ?= "./$(shell realpath --relative-to=. $(LATEST_PYNODE_DKR_DIR))"

PULUMI_DKR_VERSION ?= $(shell readlink $(LATEST_PULUMI_DKR_DIR) | grep -oP '(^.*/)?\K[^/]+(?=/?$$)')
PULUMI_DKR_DIR ?= "./$(shell realpath --relative-to=. $(LATEST_PULUMI_DKR_DIR))"

AWSMGR_DKR_VERSION ?= $(shell readlink $(LATEST_AWSMGR_DKR_DIR) | grep -oP '(^.*/)?\K[^/]+(?=/?$$)')
AWSMGR_DKR_DIR ?= "./$(shell realpath --relative-to=. $(LATEST_AWSMGR_DKR_DIR))"

VICE_DKR_VERSION ?= $(shell readlink $(LATEST_VICE_DKR_DIR) | grep -oP '(^.*/)?\K[^/]+(?=/?$$)')
VICE_DKR_DIR ?= "./$(shell realpath --relative-to=. $(LATEST_VICE_DKR_DIR))"

## for apple uncomment 
# PLATFORMS := linux/amd64,linux/arm64
PLATFORMS := linux/amd64
LOCAL_PLATFORM ?= linux/arm64

APPSTREAM_LAMBDA_API := "$(APPSTREAM_LAMBDA_ROOT_URL)$(APPSTREAM_API)"
APPSTREAM_LAMBDA_API := $(shell echo $(APPSTREAM_LAMBDA_API) | sed "s/'//g")
# Define the Dockerfile name
# DOCKERFILE := $(DOCKER_DIR)/Dockerfile


VICE_WHL_APP := $(shell ls -lhtp $(CURDIR)/src/flask/dist/*.whl 2>/dev/null | head -n1 | awk '{print $$9}' || true)
NODE_TGZ_APP := $(shell ls -lhtp $(CURDIR)/src/ui/dist/*.tgz 2>/dev/null | head -n1 | awk '{print $$9}' || true)

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

ifeq ($(NOPULL),yes)
PULLFLAG := --pull=false
else
PULLFLAG :=
endif

ifeq ($(LOCAL),yes)
LOADFLAG := --load
PLATFORMS := $(LOCAL_PLATFORM)
else
LOADFLAG :=
endif

DKR_ENV_OPTIONS := --env "AWS_KMS_KEY=$(AWS_KMS_KEY)" \
			--env "AWS_ACCESS_KEY_ID=$(AWS_ACCESS_KEY_ID)" \
			--env "AWS_SECRET_ACCESS_KEY=$(AWS_SECRET_ACCESS_KEY)" \
			--env "AWS_DEFAULT_REGION=$(AWS_DEFAULT_REGION)" \
			--env "AWS_DEFAULT_PROFILE=$(AWS_DEFAULT_PROFILE)"

# No files are created
.PHONY: all show-vars \
setup-yarn-cache-volume \
build-pynode-image clean-pynode-image push-pynode-image shell-pynode-image \
build-pulumi-image clean-pulumi-image push-pulumi-image shell-pulumi-image \
build-awsmgr-image push-awsmgr-image shell-awsmgr-image \
build-vice-image push-vice-image shell-vice-image shell-gunicorn-vice-image \
build-flask-app compile build start shell clean harbor-pull harbor-start \
harbor-shell harbor-shell-ni harbor-login
# $(error NODE_TGZ_APP is unset or empty!)
all:
	$(NOECHO) $(NOOP)

show-pynode-vars:
	@echo "LATEST_PYNODE_DKR_DIR: $(LATEST_PYNODE_DKR_DIR)"
	@echo "   PYNODE_DKR_VERSION: $(PYNODE_DKR_VERSION)"
	@echo "       PYNODE_DKR_DIR: $(PYNODE_DKR_DIR)"
	@echo ""

show-pulumi-vars:
	@echo "LATEST_PULUMI_DKR_DIR: $(LATEST_PULUMI_DKR_DIR)"
	@echo "   PULUMI_DKR_VERSION: $(PULUMI_DKR_VERSION)"
	@echo "       PULUMI_DKR_DIR: $(PULUMI_DKR_DIR)"
	@echo ""

show-awsmgr-vars:
	@echo "LATEST_AWSMGR_DKR_DIR: $(LATEST_AWSMGR_DKR_DIR)"
	@echo "   AWSMGR_DKR_VERSION: $(AWSMGR_DKR_VERSION)"
	@echo "       AWSMGR_DKR_DIR: $(AWSMGR_DKR_DIR)"
	@echo ""

show-vice-vars:
	@echo "LASTEST_VICE_DKR_DIR: $(LATEST_VICE_DKR_DIR)"
	@echo "    VICE_DKR_VERSION: $(VICE_DKR_VERSION)"
	@echo "        VICE_DKR_DIR: $(VICE_DKR_DIR)"
	@echo ""

show-vars: show-pynode-vars show-pulumi-vars show-awsmgr-vars show-vice-vars
# @echo "DOCKERHUB_USER: $(DOCKERHUB_USER)"

### DEBUGGING ISSUES
reset-docker-mybuilder:
	@docker buildx rm $(BUILDX_NAME)
	@docker buildx create $(BUILDX_NAME) --use
## PYNODE
# Build pynode (Python/Node & Golang)
build-pynode-image:
	@echo "Building pynode $(PYNODE_DKR_VERSION) image"
	cd $(PYNODE_DKR_DIR); \
	docker buildx use $(BUILDX_NAME); \
	docker buildx build \
		--label pynode \
		--platform $(PLATFORMS) \
		--build-arg PYNODE_PARENT_IMAGE=$(PYNODE_PARENT_IMAGE) \
		--build-arg PYNODE_PARENT_TAG=$(PYNODE_PARENT_TAG) \
		$(CACHEFLAG) $(LOADFLAG) $(PULLFLAG) \
		--tag $(DOCKERHUB_USER)/pynode:$(PYNODE_DKR_VERSION)-$(GIT_HASH) \
		--tag $(DOCKERHUB_USER)/pynode:$(PYNODE_DKR_VERSION) \
    	--tag $(DOCKERHUB_USER)/pynode:latest \
		$(PUSHFLAG) .
# Tag pynode
tag-pynode-image:
	@echo "Tag $(DOCKERHUB_USER)/pynode:$(PYNODE_DKR_VERSION) as latest"
	docker tag $(DOCKERHUB_USER)/pynode:$(PYNODE_DKR_VERSION)-$(GIT_HASH) $(DOCKERHUB_USER)/pynode:$(PYNODE_DKR_VERSION)
	docker tag $(DOCKERHUB_USER)/pynode:$(PYNODE_DKR_VERSION)-$(GIT_HASH) $(DOCKERHUB_USER)/pynode:latest
# Clean pynode
clean-pynode-image:
	@echo "Cleaning images out for pynode"
	docker rmi $(DOCKERHUB_USER)/pynode:$(PYNODE_DKR_VERSION) 2>/dev/null || echo "Image pynode:$(PYNODE_DKR_VERSION) has already been removed."
	docker rmi $(DOCKERHUB_USER)/pynode:$(PYNODE_DKR_VERSION)-* 2>/dev/null || echo "Image pynode:$(PYNODE_DKR_VERSION)-* has already been removed."
	docker rmi $(DOCKERHUB_USER)/pynode:latest 2>/dev/null || echo "Image pynode:latest has already been removed."
	@echo "To complete removal, run: docker images prune -a"
# Push pynode
push-pynode-image:
	@echo "Pushing pynode $(DOCKERHUB_USER)/pynode:latest to hub.docker.com"
	cd $(PYNODE_DKR_DIR); \
	docker push $(DOCKERHUB_USER)/pynode:$(PYNODE_DKR_VERSION)-$(GIT_HASH); \
	docker push $(DOCKERHUB_USER)/pynode:$(PYNODE_DKR_VERSION); \
	docker push $(DOCKERHUB_USER)/pynode:latest
# Shell pynode
shell-pynode-image:
	@echo "Running pynode $(DOCKERHUB_USER)/pynode:$(PYNODE_DKR_VERSION)"
	cd $(PYNODE_DKR_DIR); \
	docker run --rm -it hagan/pynode:latest /bin/sh
## PULUMI
# Build pulumi
build-pulumi-image:
	@echo "Building pulumi $(PULUMI_DKR_VERSION) image"
	cd $(PULUMI_DKR_DIR); \
	docker buildx use $(BUILDX_NAME); \
	docker buildx build \
		--label pulumi \
		--platform $(PLATFORMS) \
		--build-arg PULUMI_VERSION=$(PULUMI_VERSION) \
		--build-arg PULUMI_PARENT_IMAGE=hagan/pynode \
		--build-arg PULUMI_PARENT_TAG=$(PYNODE_DKR_VERSION) \
		$(CACHEFLAG) $(LOADFLAG) $(PULLFLAG) \
		--tag $(DOCKERHUB_USER)/pulumi:$(PULUMI_DKR_VERSION)-$(GIT_HASH) \
		--tag $(DOCKERHUB_USER)/pulumi:$(PULUMI_DKR_VERSION) \
		--tag $(DOCKERHUB_USER)/pulumi:latest \
		$(PUSHFLAG) .
# Tag pulumi
tag-pulumi-image:
	@echo "Tag $(DOCKERHUB_USER)/pulumi:$(PULUMI_DKR_VERSION) as latest"
	docker tag $(DOCKERHUB_USER)/pulumi:$(PULUMI_DKR_VERSION)-$(GIT_HASH) $(DOCKERHUB_USER)/pulumi:latest
	docker tag $(DOCKERHUB_USER)/pulumi:$(PULUMI_DKR_VERSION)-$(GIT_HASH) $(DOCKERHUB_USER)/pulumi:$(PULUMI_DKR_VERSION)
# Clean pulumi
clean-pulumi-image:
	@echo "Cleaning images out for pulumi"
	docker rmi $(DOCKERHUB_USER)/pulumi:$(PULUMI_DKR_VERSION) 2>/dev/null || echo "Image pulumi:$(PULUMI_DKR_VERSION) has already been removed."
	docker rmi $(DOCKERHUB_USER)/pulumi:$(PULUMI_DKR_VERSION)-* 2>/dev/null || echo "Image pulumi:$(PULUMI_DKR_VERSION)-* has already been removed."
	docker rmi $(DOCKERHUB_USER)/pulumi:latest 2>/dev/null || echo "Image pulumi:latest has already been removed."
	@echo "To complete removal, run: docker images prune -a"
# Push pulumi
push-pulumi-image:
	@echo "Pushing pulumi $(DOCKERHUB_USER)/pulumi:latest to hub.docker.com"
	cd $(PULUMI_DKR_DIR); \
	docker push $(DOCKERHUB_USER)/pulumi:$(PULUMI_DKR_VERSION)-$(GIT_HASH); \
	docker push $(DOCKERHUB_USER)/pulumi:$(PULUMI_DKR_VERSION); \
	docker push $(DOCKERHUB_USER)/pulumi:latest
# shell pulumi
shell-pulumi-image:
	@echo "Running pulumi $(DOCKERHUB_USER)/pulumi:$(PULUMI_DKR_VERSION)"
	cd $(PULUMI_DKR_DIR); \
	docker run --rm -it hagan/pulumi:latest /bin/sh
## AWSMGR
# build awsmgr
build-awsmgr-image: all
	@( cd $(CURDIR)/src/flask; poetry export -f requirements.txt --output requirements.txt )
	@echo "Building awsmgr $(AWSMGR_DKR_VERSION) image"
	@( cd $(AWSMGR_DKR_DIR); cp $(CURDIR)/src/ui/yarn.lock .; cp $(CURDIR)/src/ui/package.json . )
	@mv $(CURDIR)/src/flask/requirements.txt .

	@cd $(AWSMGR_DKR_DIR) \
	&& docker buildx use $(BUILDX_NAME) \
	&& DOCKER_BUILDKIT=1 docker buildx build \
		--progress=plain \
		--label awsmgr \
		--platform $(PLATFORMS) \
		--build-arg AWSMGR_PARENT_IMAGE=hagan/pulumi \
		--build-arg AWSMGR_PARENT_TAG=$(PULUMI_DKR_VERSION) \
		$(CACHEFLAG) $(LOADFLAG) $(PULLFLAG) \
		--tag $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_DKR_VERSION)-$(GIT_HASH) \
		--tag $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_DKR_VERSION) \
		--tag $(DOCKERHUB_USER)/awsmgr:latest \
		$(PUSHFLAG) .
# Tag awsmgr
tag-awsmgr-image:
	@echo "Tag $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_DKR_VERSION) as latest"
	docker tag $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_DKR_VERSION)-$(GIT_HASH) $(DOCKERHUB_USER)/awsmgr:latest
	docker tag $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_DKR_VERSION)-$(GIT_HASH) $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_DKR_VERSION)
# clean awsmgr
clean-awsmgr-image:
	@echo "Cleaning images out for awsmgr"
	docker rmi $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_DKR_VERSION) 2>/dev/null || echo "Image awsmgr:$(AWSMGR_DKR_VERSION) has already been removed."
	docker rmi $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_DKR_VERSION)-* 2>/dev/null || echo "Image awsmgr:$(AWSMGR_DKR_VERSION)-* has already been removed."
	docker rmi $(DOCKERHUB_USER)/awsmgr:latest 2>/dev/null || echo "Image awsmgr:latest has already been removed."
	@echo "To complete removal, run: docker images prune -a"
# push awsmgr
push-awsmgr-image:
	@echo "Pushing awsmgr $(DOCKERHUB_USER)/awsmgr:latest to hub.docker.com"
	cd $(AWSMGR_DKR_DIR); \
	docker push $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_DKR_VERSION); \
	docker push $(DOCKERHUB_USER)/awsmgr:latest
# shell awsmgr
shell-awsmgr-image:
	@echo "Running awsmgr $(DOCKERHUB_USER)/awsmgr:latest"
	cd $(AWSMGR_DKR_DIR); \
	docker run --rm -it hagan/awsmgr:latest /bin/sh
## vice
# build vice
build-vice-image: all build-flask-app build-node-app
	@if [ -z "$(NODE_TGZ_APP)" ]; then (echo "NODE_TGZ_APP is unset or empty" && exit 1); fi
	@echo "$(date +%T) - Building viceawsmg $(VICE_DKR_VERSION) image from $(VICE_DKR_DIR)/Dockerfile!"
	@echo "FLAGS: $(CACHEFLAG) $(LOADFLAG) $(PULLFLAG) $(PUSHFLAG)"
	@if [ ! -f "$(NODE_TGZ_APP)" ]; then (echo "ERROR: $(NODE_TGZ_APP) not found!" && exit 1); fi
	@docker buildx use $(BUILDX_NAME); \
	DOCKER_BUILDKIT=1 docker buildx build \
		--progress=plain \
		-f $(VICE_DKR_DIR)/Dockerfile \
		--label viceawsmgr \
		--platform $(PLATFORMS) \
		--build-arg VICE_PARENT_IMAGE=hagan/awsmgr \
		--build-arg VICE_PARENT_TAG=$(AWSMGR_DKR_VERSION) \
		--build-arg VICE_DKR_VERSION=$(VICE_DKR_VERSION) \
		--build-arg VICE_DKR_DIR=$(VICE_DKR_DIR) \
		$(CACHEFLAG) $(LOADFLAG) $(PULLFLAG) \
		--tag $(DOCKERHUB_USER)/viceawsmgr:$(VICE_DKR_VERSION) \
		--tag $(DOCKERHUB_USER)/viceawsmgr:$(VICE_DKR_VERSION)-$(GIT_HASH) \
		--tag $(DOCKERHUB_USER)/viceawsmgr:latest \
		$(PUSHFLAG) .
# vice - clean image
clean-vice-image:
	@echo "Cleaning images out for vice"
	docker rmi $(DOCKERHUB_USER)/viceawsmgr:$(VICE_DKR_VERSION) 2>/dev/null || echo "Image viceawsmgr:$(VICE_DKR_VERSION) has already been removed."
	docker rmi $(DOCKERHUB_USER)/viceawsmgr:$(VICE_DKR_VERSION)-$(GIT_HASH) 2>/dev/null || echo "Image viceawsmgr:$(VICE_DKR_VERSION)-$(GIT_HASH) has already been removed."
	docker rmi $(DOCKERHUB_USER)/viceawsmgr:latest 2>/dev/null || echo "Image viceawsmgr:latest has already been removed."
	@echo "To complete removal, run: docker images prune -a"

push-vice-image:
	@echo "Pushing viceawsmgr $(DOCKERHUB_USER)/viceawsmgr:latest to hub.docker.com"
	cd $(VICE_DKR_DIR); \
	docker push $(DOCKERHUB_USER)/viceawsmgr:$(VICE_DKR_VERSION); \
	docker push $(DOCKERHUB_USER)/viceawsmgr:latest

shell-vice-image:
	@echo "Running viceawsmgr $(DOCKERHUB_USER)/viceawsmgr:$(VICE_DKR_VERSION) -- RUNSHELL=$(RUNSHELL)"
	cd $(VICE_DKR_DIR); \
	docker ps --filter "name=vice" | grep vice >/dev/null 2>&1 \
		&& docker exec \
		  $(DKR_ENV_OPTIONS) \
		  -it vice /usr/bin/bash \
		|| docker run \
			--env "RUNSHELL=$(RUNSHELL)" \
			$(DKR_ENV_OPTIONS) \
			--name vice \
			-p 80:80 \
			-p 8080:8080 \
			-p 2022:22 \
			--volume $(CURDIR)/src/ui/dist:/mnt/dist/npms \
			--volume $(CURDIR)/src/flask/dist:/mnt/dist/wheels \
			--rm -it $(DOCKERHUB_USER)/viceawsmgr:latest /bin/sh

history-vice-image:
	@echo "docker history $(DOCKERHUB_USER)/viceawsmgr:latest"
	@docker history $(DOCKERHUB_USER)/viceawsmgr:latest

#
# 		/usr/bin/bash
# 	    'su - gunicorn -c ". /home/gunicorn/envs/flask-env/bin/activate && export FLASK_APP='awsmgr.app' && exec /usr/bin/bash"'

shell-gunicorn-vice-image:
	@echo "Running viceawsmgr $(DOCKERHUB_USER)/viceawsmgr:$(VICE_DKR_VERSION) as gunicorn user"
	cd $(VICE_DKR_DIR); \
	docker ps --filter "name=vice" | grep vice >/dev/null 2>&1 \
	  && docker exec \
	    $(DKR_ENV_OPTIONS) \
		-it vice /usr/bin/su \
		--whitelist-environment AWS_KMS_KEY \
		--whitelist-environment AWS_ACCESS_KEY_ID \
		--whitelist-environment AWS_SECRET_ACCESS_KEY \
		--whitelist-environment AWS_DEFAULT_REGION \
		--whitelist-environment AWS_SESSION_TOKEN \
		-l gunicorn \
	  || { echo "ERROR: vice image not running!"; exit 1; }

shell-cyverse-vice-image:
	@echo "Running viceawsmgr $(DOCKERHUB_USER)/viceawsmgr:$(VICE_DKR_VERSION) as cyverse user"
	cd $(VICE_DKR_DIR); \
	docker ps --filter "name=vice" | grep vice >/dev/null 2>&1 \
	  && docker exec \
	    $(DKR_ENV_OPTIONS) \
		-it vice /usr/bin/su \
		--whitelist-environment AWS_KMS_KEY \
		--whitelist-environment AWS_ACCESS_KEY_ID \
		--whitelist-environment AWS_SECRET_ACCESS_KEY \
		--whitelist-environment AWS_DEFAULT_REGION \
		--whitelist-environment AWS_SESSION_TOKEN \
		-l cyverse \
	  || { echo "ERROR: vice image not running!"; exit 1; }


build-flask-app:
	@echo "Compile/build package for flask..."
	cd $(FLASK_DIR) && \
	./build.sh

## helper shells into our (running vice) and inserts a new version of the awsmgr!
reload-vice-flask-app: build-flask-app
	@echo "Inserting $(VICE_WHL_APP)"
	@docker ps --filter "name=vice" | grep vice >/dev/null 2>&1 \
	&& docker cp $(VICE_WHL_APP) vice:/mnt/dist/wheels \
	&& docker exec -it vice /bin/sh -c 'su - gunicorn -c /usr/local/bin/update-wheel.sh' \
	&& docker exec -it vice /bin/sh -c 'su - cyverse -c /usr/local/bin/update-wheel.sh' \
	&& docker exec -it vice /bin/sh -c 'supervisorctl restart gunicorn' \
	|| echo "ERROR: vice is not running, try 'make shell-vice-image'"


shell-node-vice-image:
	@echo "Running viceawsmgr $(DOCKERHUB_USER)/viceawsmgr:$(VICE_DKR_VERSION) as node user"
	cd $(VICE_DKR_DIR); \
	docker ps --filter "name=vice" | grep vice >/dev/null 2>&1 \
	  && docker exec -it --user node vice /usr/bin/bash \
	  || echo "vice image not running!"

build-node-app:
	@echo "Compile/build package for Express/NextJS"
	$(NODE_DIR)/build.sh

reload-vice-node-app: build-node-app
	@if [ -z "$(NODE_TGZ_APP)" ]; then (echo "NODE_TGZ_APP is unset or empty" && exit 1); fi
	@echo "Building viceawsmg $(VICE_DKR_VERSION) image"
	@if [ ! -f "$(NODE_TGZ_APP)" ]; then (echo "ERROR: $(NODE_TGZ_APP) not found!" && exit 1); fi
	@echo "Inserting $(NODE_TGZ_APP)"
	@docker ps --filter "name=vice" | grep vice >/dev/null 2>&1 \
	&& docker cp $(NODE_TGZ_APP) vice:/mnt/dist/npms \
	&& docker exec -it vice /bin/sh -c 'su - node -c /usr/local/bin/update-npm.sh' \
	|| { echo "Error while updating package!"; exit 1; } \
	&& docker exec -it vice /bin/sh -c 'supervisorctl restart express' \
	|| { echo "ERROR: trying to restart express"; exit 1; }

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

#  		--env "SOCKET_FILE=/tmp/node-nextjs.socket"

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
	docker buildx prune
# docker rm -f $(DOCKER_IMAGE)
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
