# Cyverse AWS Manager

version: 0.0.1

#### Git submodules/HOWTO

To clone repo:
```
  git clone --recurse-submodules <repo url>
```

#### Git LFS

MacOS/OSX
$ brew install git-lfs

Linux/Debian
$ apt install git-lfs

And you do not need to run `git lfs install` as hooks are already in .git/hook or .husky folders.

## Compiling docker images

#### Setup our builder environment

  docker buildx create --name mybuilder --use
  docker buildx inspect --bootstrap
  docker login

#### Create images for hub

Warning this takes time to compile, 6+ hours. Only needed once, use hub.docker.com instead

    1) adjust config.mk to reflect docker hub user etc...
    2) make NOCACHE=yes DOCKERHUB=yes build-pynode-image
    3) make NOCACHE=yes DOCKERHUB=yes build-pulumi-image
    4) make NOCACHE=yes DOCKERHUB=yes build-awsmgr-image
    5) make NOCACHE=yes DOCKERHUB=yes build-vice-image

Note: Only recompile step 5 unless you need to modify the Python/NodeJS/AWS/Pulumi root alpine Image. Only takes ~1 minute

#### Simplify C&C of AWS resources

4 elements of project

  1) VICE applicaiton for Cyverse infrasturcture (cy-aws-vice)
  2) Lambda functions for AWS C&C
  3) Flask UX application for vice app


