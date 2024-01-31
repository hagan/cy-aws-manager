COMMENT ?= 'fixup'
## NOTE: These are also located in the github/actions Repository variables!
SRC_DOCKER_IMAGE ?= 'hagan/awsmgr'
SRC_DOCKER_VER ?= 'v0.0.3'

# paths to build our "latest" docker image
DOCKER_IMAGE=viceamazonmgr
## how can we use symbolic link "latest" intead? does not work with buildx
DOCKER_TAG=0.0.1
DOCKER_DIR=./src/vice/0.0.1
FLASK_DIR=./src/flask
VICE_DIR=./src/vice
NVM_DIR=${HOME}/.nvm

CONTEXT=.

# PIP_WHEEL_FILENAME='appstreamer-0.1.1-py3-none-any.whl'
# APPSTREAM_API='/api/v1/appstream'
# APPSTREAM_LAMBDA_ROOT_URL=''
# STATIC_ROOT='/var/www/static'