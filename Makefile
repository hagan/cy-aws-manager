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

PYNODE_PARENT_IMAGE := python
PYNODE_PARENT_TAG := 3.11.9-bookworm

PYNODE_DKR_VERSION ?= $(shell readlink $(LATEST_PYNODE_DKR_DIR) | grep -oP '(^.*/)?\K[^/]+(?=/?$$)')
PYNODE_DKR_DIR ?= "./$(shell realpath --relative-to=. $(LATEST_PYNODE_DKR_DIR))"

PULUMI_DKR_VERSION ?= $(shell readlink $(LATEST_PULUMI_DKR_DIR) | grep -oP '(^.*/)?\K[^/]+(?=/?$$)')
PULUMI_DKR_DIR ?= "./$(shell realpath --relative-to=. $(LATEST_PULUMI_DKR_DIR))"

AWSMGR_DKR_VERSION ?= $(shell readlink $(LATEST_AWSMGR_DKR_DIR) | grep -oP '(^.*/)?\K[^/]+(?=/?$$)')
AWSMGR_DKR_DIR ?= "./$(shell realpath --relative-to=. $(LATEST_AWSMGR_DKR_DIR))"

VICE_DKR_VERSION ?=  $(shell readlink $(LATEST_VICE_DKR_DIR) | grep -oP '(^.*/)?\K[^/]+(?=/?$$)')
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
NODE_TGZ_APP := $(shell find $(realpath $(CURDIR)/src/ui/dist) -name '*.tgz' -type f -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2- || true)

ifeq ($(NOCACHE),yes)
CACHEFLAG := --no-cache
else
CACHEFLAG :=
endif

# ifeq ($(SKIPDOCKERHUB),yes)
# PUSHFLAG :=
# else
# PUSHFLAG := --push
# endif

ifeq ($(NOPULL),yes)
PULLFLAG := --pull=false
else
PULLFLAG :=
endif

# ifeq ($(LOADLOCAL),yes)
# LOADFLAG := --load
# @echo "cannot use push flag with LOADLOCAL=yes"
# PUSHFLAG :=
# PLATFORMS := $(LOCAL_PLATFORM)
# else
# LOADFLAG :=
# endif

PUSHFLAG :=
PYNODETAGS :=
PULUMITAGS :=
AWSMGRTAGS :=
VICEAWSMGRTAGS :=
SKIPAWSAUTH :=
REGISTRY := localhost:5000/

## Currently Harbor is only letting me post to "appstream"
ifeq ($(HARBORREGISTRY),yes)
# PYNODETAGS (none)
# PULUMITAGS (none)
# AWSMGRTAGS (none)
	PUSHFLAG := --push
	VICEAWSMGRTAGS := $(VICEAWSMGRTAGS) \
		--tag harbor.cyverse.org/vice/appstream:latest

	REGISTRY := harbor.cyverse.org/
endif

ifeq ($(DOCKERREGISTRY),yes)
	PUSHFLAG := --push
	PYNODETAGS :=  $(PYNODETAGS) \
		--tag $(DOCKERHUB_USER)/pynode:$(PYNODE_DKR_VERSION)-$(GIT_HASH) \
		--tag $(DOCKERHUB_USER)/pynode:$(PYNODE_DKR_VERSION) \
		--tag $(DOCKERHUB_USER)/pynode:latest
	PULUMITAGS := $(PULUMITAGS) \
		--tag $(DOCKERHUB_USER)/pulumi:$(PULUMI_DKR_VERSION)-$(GIT_HASH) \
		--tag $(DOCKERHUB_USER)/pulumi:$(PULUMI_DKR_VERSION) \
		--tag $(DOCKERHUB_USER)/pulumi:latest
	AWSMGRTAGS := $(AWSMGRTAGS) \
		--tag $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_DKR_VERSION)-$(GIT_HASH) \
		--tag $(DOCKERHUB_USER)/awsmgr:$(AWSMGR_DKR_VERSION) \
		--tag $(DOCKERHUB_USER)/awsmgr:latest
	VICEAWSMGRTAGS := $(VICEAWSMGRTAGS) \
		--tag $(DOCKERHUB_USER)/viceawsmgr:$(VICE_DKR_VERSION) \
		--tag $(DOCKERHUB_USER)/viceawsmgr:$(VICE_DKR_VERSION)-$(GIT_HASH) \
		--tag $(DOCKERHUB_USER)/viceawsmgr:latest
	REGISTRY := $(DOCKERHUB_USER)/
endif


ifeq ($(LOCALREGISTRY),yes)
	PUSHFLAG := --push
	PYNODETAGS :=  $(PYNODETAGS) \
		--tag localhost:5000/pynode:latest
	PULUMITAGS := $(PULUMITAGS) \
		--tag localhost:5000/pulumi:latest
	AWSMGRTAGS := $(AWSMGRTAGS) \
		--tag localhost:5000/awsmgr:latest
	VICEAWSMGRTAGS := $(VICEAWSMGRTAGS) \
		--tag localhost:5000/viceawsmgr:latest
endif

ifeq ($(SKIPNODEBUILD),yes)
NODEBUILD :=
else
NODEBUILD := build-node-app
endif

ifeq ($(SKIPFLASKBUILD),yes)
FLASKBUILD :=
else
FLASKBUILD := build-flask-app
endif

ifeq ($(SKIPAWSAUTH),yes)
SKIP_AUTH_TEST_ENV := --env "SKIP_AUTH_TEST=true"
else
SKIP_AUTH_TEST_ENV :=
endif

## don't forget to whitelist these in entrypoint.sh!!
DKR_ENV_OPTIONS := \
			--env AWS_ACCOUNT_ID \
			--env AWS_ACCESS_KEY_ID \
			--env AWS_SECRET_ACCESS_KEY \
			--env AWS_SESSION_TOKEN \
			--env AWS_DEFAULT_REGION \
			--env AWS_CREDENTIAL_EXPIRATION \
			--env APIGATEWAY_NAME \
			--env APIGATEWAY_API_KEY_NAME \
			--env APIGATEWAY_STAGE
# --env SKIP_AUTH_TEST=true

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
		--build-arg PYNODE_NAME=$(DOCKERHUB_USER)/pynode \
		--build-arg PYNODE_TAG=$(PYNODE_DKR_VERSION)-$(GIT_HASH) \
		--build-arg CACHEBUST=$(shell date +%s) \
		$(CACHEFLAG) $(LOADFLAG) $(PULLFLAG) $(PYNODETAGS) \
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
	docker run --rm -it $(REGISTRY)pynode:latest /bin/sh
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
		--build-arg PULUMI_NAME=$(DOCKERHUB_USER)/pulumi \
		--build-arg PULUMI_TAG=$(PULUMI_DKR_VERSION)-$(GIT_HASH) \
		--build-arg CACHEBUST=$(shell date +%s) \
		$(CACHEFLAG) $(LOADFLAG) $(PULLFLAG) $(PULUMITAGS) \
		$(PUSHFLAG) .
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
	@echo "Running pulumi $(REGISTRY)pulumi:$(PULUMI_DKR_VERSION)"
	cd $(PULUMI_DKR_DIR); \
	docker run --rm -it $(REGISTRY)pulumi:latest /bin/sh
## AWSMGR
# build awsmgr
build-awsmgr-image: all $(NODEBUILD)
	@if [ -z "$(NODE_TGZ_APP)" ]; then (echo "NODE_TGZ_APP is unset or empty" && exit 1); fi
	@( \
		echo "Creating requirements.txt from poetry pyproject.toml file.."; \
		cd $(CURDIR)/src/flask; \
		poetry export -f requirements.txt --output requirements.txt; \
		cd $(CURDIR)/$(AWSMGR_DKR_DIR); \
		mv $(CURDIR)/src/flask/requirements.txt .; \
	)

	@( \
		echo "Copying yarn files from $(CURDIR)/src/ui into $(AWSMGR_DKR_DIR) for awsmgr docker container build step.."; \
		cd $(AWSMGR_DKR_DIR); \
		cp -f $(CURDIR)/src/ui/yarn.lock .; \
		cp -f $(CURDIR)/src/ui/package.json .; \
		cp -f $(CURDIR)/src/ui/.yarnrc.yml .; \
		cp -rpf $(CURDIR)/src/ui/.yarn .; \
	)
	@echo "Copying $(NODE_TGZ_APP) into awsmgr space for container build step.."
	@cp $(NODE_TGZ_APP) $(CURDIR)/src/vice/dockerhub/awsmgr/latest/.
	@echo "Building awsmgr $(AWSMGR_DKR_VERSION) image"
	@cd $(AWSMGR_DKR_DIR) \
		&& docker buildx use $(BUILDX_NAME) \
		&& DOCKER_BUILDKIT=1 docker buildx build \
			--progress=plain \
			--label awsmgr \
			--platform $(PLATFORMS) \
			--build-arg AWSMGR_PARENT_IMAGE=hagan/pulumi \
			--build-arg AWSMGR_PARENT_TAG=$(PULUMI_DKR_VERSION) \
			--build-arg AWSMGR_NAME=$(DOCKERHUB_USER)/awsmgr \
			--build-arg AWSMGR_TAG=$(AWSMGR_DKR_VERSION)-$(GIT_HASH) \
			--build-arg CACHEBUST=$(shell date +%s) \
			$(CACHEFLAG) $(LOADFLAG) $(PULLFLAG) $(AWSMGRTAGS) \
			$(PUSHFLAG) .
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
	@echo "Running awsmgr $(REGISTRY)awsmgr:latest"
	cd $(AWSMGR_DKR_DIR); \
	docker run --rm -it $(REGISTRY)awsmgr:latest /bin/sh
## vice
# build vice
compress-vice-package:
	@echo "Compressing $(VICE_DKR_DIR)/package -> $(VICE_DKR_DIR)/package.tar.gz"
	@test -f "$(VICE_DKR_DIR)/package.tar.gz" && { rm $(VICE_DKR_DIR)/package.tar.gz && echo "removed $(VICE_DKR_DIR)/package.tar.gz"; } || true
	@tar cvfz $(VICE_DKR_DIR)/package.tar.gz --owner=root --group=root -C $(VICE_DKR_DIR)/package .

build-vice-image: all compress-vice-package $(FLASKBUILD) $(NODEBUILD)
	@if [ -z "$(NODE_TGZ_APP)" ]; then (echo "NODE_TGZ_APP is unset or empty" && exit 1); fi
	@echo "$(date +%T) - Building viceawsmg $(VICE_DKR_VERSION) image from $(VICE_DKR_DIR)/Dockerfile!"
	@echo "FLAGS: $(CACHEFLAG) $(LOADFLAG) $(PULLFLAG) $(PUSHFLAG)"
	@if [ ! -f "$(NODE_TGZ_APP)" ]; then (echo "ERROR: $(NODE_TGZ_APP) not found!" && exit 1); fi
	@docker buildx use $(BUILDX_NAME); \
		DOCKER_BUILDKIT=1 docker buildx build \
		--progress=plain \
		-f $(VICE_DKR_DIR)/Dockerfile \
		--label $(VICE_NAME) \
		--platform $(PLATFORMS) \
		--build-arg VICE_PARENT_IMAGE=hagan/awsmgr \
		--build-arg VICE_PARENT_TAG=$(AWSMGR_DKR_VERSION) \
		--build-arg VICE_NAME=viceawsmgr \
		--build-arg VICE_TAG=$(VICE_DKR_VERSION)-$(GIT_HASH) \
		--build-arg VICE_DKR_DIR=$(VICE_DKR_DIR) \
		--build-arg CACHEBUST=$(shell date +%s) \
		$(CACHEFLAG) $(LOADFLAG) $(PULLFLAG) $(VICEAWSMGRTAGS) \
		$(PUSHFLAG) .
# vice - clean image
clean-vice-image:
	@echo "Cleaning images out for vice"
	docker rmi $(DOCKERHUB_USER)/viceawsmgr:$(VICE_DKR_VERSION) 2>/dev/null || echo "Image viceawsmgr:$(VICE_DKR_VERSION) has already been removed."
	docker rmi $(DOCKERHUB_USER)/viceawsmgr:$(VICE_DKR_VERSION)-$(GIT_HASH) 2>/dev/null || echo "Image viceawsmgr:$(VICE_DKR_VERSION)-$(GIT_HASH) has already been removed."
	docker rmi $(DOCKERHUB_USER)/viceawsmgr:latest 2>/dev/null || echo "Image viceawsmgr:latest has already been removed."
	@echo "To complete removal, run: docker images prune -a"

docker-push-vice-image:
	@echo "Pushing viceawsmgr $(DOCKERHUB_USER)/viceawsmgr:latest to hub.docker.com"
	cd $(VICE_DKR_DIR); \
	docker push $(DOCKERHUB_USER)/viceawsmgr:$(VICE_DKR_VERSION); \
	docker push $(DOCKERHUB_USER)/viceawsmgr:latest

harbor-push-vice-image: harbor-login
	@echo "Pushing viceawsmgr $(DOCKERHUB_USER)/viceawsmgr:latest to harbor"
	docker tag $(DOCKERHUB_USER)/viceawsmgr:latest harbor.cyverse.org/vice/appstream:latest
	docker push harbor.cyverse.org/vice/appstream:latest

shell-vice-image-sim:
	@echo "Running viceawsmgr $(REGISTRY)viceawsmgr:$(VICE_DKR_VERSION) 'sim' -- RUNSHELL=$(RUNSHELL)"
	cd $(VICE_DKR_DIR); \
	docker ps --filter "name=vice" | grep vice >/dev/null 2>&1 \
		&& docker exec \
			$(DKR_ENV_OPTIONS) \
			-it vice /usr/bin/bash \
		|| docker run \
			$(DKR_ENV_OPTIONS) \
			--quiet \
			--name vice \
			-p 80:80 \
			--rm -it $(REGISTRY)viceawsmgr:latest /bin/sh

shell-vice-image:
	@echo "Running viceawsmgr $(REGISTRY)viceawsmgr:$(VICE_DKR_VERSION) -- RUNSHELL=$(RUNSHELL)"
	cd $(VICE_DKR_DIR); \
	docker ps --filter "name=vice" | grep vice >/dev/null 2>&1 \
		&& docker exec \
			$(DKR_ENV_OPTIONS) \
			-it vice /usr/bin/bash \
		|| docker run \
			--env "RUNSHELL=$(RUNSHELL)" \
			$(DKR_ENV_OPTIONS) \
			$(SKIP_AUTH_TEST_ENV) \
			--name vice \
			-p 80:80 \
			-p 8080:8080 \
			-p 2022:22 \
			--volume $(CURDIR)/src/ui/dist:/mnt/dist/npms \
			--volume $(CURDIR)/src/flask/dist:/mnt/dist/wheels \
			--rm -it $(REGISTRY)viceawsmgr:latest /bin/sh

history-vice-image:
	@echo "docker history $(REGISTRY)viceawsmgr:latest"
	@docker history $(REGISTRY)viceawsmgr:latest

#
# 		/usr/bin/bash
# 	    'su - gunicorn -c ". /home/gunicorn/envs/flask-env/bin/activate && export FLASK_APP='awsmgr.app' && exec /usr/bin/bash"'

shell-gunicorn-vice-image:
	@echo "Running viceawsmgr $(REGISTRY)viceawsmgr:$(VICE_DKR_VERSION) as gunicorn user"
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
	@echo "Running viceawsmgr $(REGISTRY)viceawsmgr:$(VICE_DKR_VERSION) as cyverse user"
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


echo-creds-cyverse-vice-image:
	@cd $(VICE_DKR_DIR); \
	docker ps --filter "name=vice" | grep vice >/dev/null 2>&1 \
	  && docker exec \
	    $(DKR_ENV_OPTIONS) \
		-it vice /usr/bin/su \
		-l cyverse -c "echo '$${AWS_ACCESS_KEY_ID}'"

shell-creds-cyverse-vice-image:
	@echo "SERIOUSLY LIKE WTF"
	ASSIGNTHIS ?= "hahahah"

build-flask-app:
	@echo "Compile/build package for flask..."
	cd $(FLASK_DIR) && \
	./build.sh

## helper shells into our (running vice) and inserts a new version of the awsmgr!
reload-vice-flask-app: $(FLASKBUILD)
	@echo "Inserting $(VICE_WHL_APP)"
	@docker ps --filter "name=vice" | grep vice >/dev/null 2>&1 \
	&& docker cp $(VICE_WHL_APP) vice:/mnt/dist/wheels \
	&& docker cp $(VICE_DKR_DIR)/package/usr/local/bin/update-wheel.sh vice:/usr/local/bin/update-wheel.sh \
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
#
reload-vice-node-app: $(NODEBUILD)
	@if [ -z "$(NODE_TGZ_APP)" ]; then (echo "NODE_TGZ_APP is unset or empty" && exit 1); fi
	@echo "Building viceawsmg $(VICE_DKR_VERSION) image"
	@if [ ! -f "$(NODE_TGZ_APP)" ]; then (echo "ERROR: $(NODE_TGZ_APP) not found!" && exit 1); fi
	@echo "Inserting $(NODE_TGZ_APP)"
	@docker ps --filter "name=vice" | grep vice >/dev/null 2>&1 \
	&& docker cp $(NODE_TGZ_APP) vice:/mnt/dist/npms \
	&& docker cp $(VICE_DKR_DIR)/package/usr/local/bin/update-npm.sh vice:/usr/local/bin/update-npm.sh \
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

# --env "SOCKET_FILE=/tmp/node-nextjs.socket"

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
	@docker login harbor.cyverse.org
