## Note: used by github actions

LOCAL_PLATFORM=linux/amd64
DOCKERHUB_USER=hagan
COMMENT='fixup'
## NOTE: These are also located in the github/actions Repository variables!
VICE_PARENT_IMAGE='hagan/awsmgr'
VICE_PARENT_TAG='latest'

PULUMI_VERSION=3.107.0

# paths to build our "latest" docker image
VICE_NAME=viceawsmgr

## how can we use symbolic link "latest" intead? does not work with buildx
# DOCKER_TAG=0.0.1
# DOCKER_DIR=./src/vice/0.0.1
FLASK_DIR=./src/flask
NODE_DIR=./src/ui
VICE_DIR=./src/vice
VICE_DKR_DIR=./src/vice/versions/bookworm.v3
# NVM_DIR=${HOME}/.nvm

CONTEXT=.

# PIP_WHEEL_FILENAME='awsmgr-0.0.2-py3-none-any.whl'
# APPSTREAM_API='/api/v1/appstream'
# APPSTREAM_LAMBDA_ROOT_URL=''
# STATIC_ROOT='/var/www/static'