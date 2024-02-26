# Cyverse AWS Manager

version: 0.0.1

#### Prereqs

  * Setup direnv in your bash/zsh environment: https://direnv.net/
  * Setup pyenv or similar to setup poetry for flask -> <project>/src/flask/README.md for more info


#### Git submodules/HOWTO

To clone repo:
```
  git clone --recurse-submodules <repo url>

  # OR
  git clone <repo url> <project dir name>
  cd <project dir name>
  ## For the very first time you clone a project:
  git submodule update --init --recursive
```

To update project

```
  cd <project dir name>
  git pull
  git submodule update --recursive --remote
```

Updating project &/or submodules...
Note: Sometimes a repo submodule will become detached if you checkout the root project space (by design). To make a change and/or commit:
```
  cd <project>/src/ui; git checkout main; .. work ..; git commit -am "update react thing"; git push
  cd <project>/src/flask; git checkout main; .. work ..; git commit -am "updated flask thing"; git push
  cd <project>/src/vice; git checkout main; .. work ..; git commit -am "updated docker vice stuff"; git push
  cd <project>; git commit -am "updated all the things"; git push
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

~Warning this takes time to compile, 6+ hours. Only needed once, use hub.docker.com instead
Note: Now awsmgr takes about 30mins... After modifying pynode/pulumi to take less time, taking longer to build the image, dunno why

    1) adjust config.mk to reflect docker hub user etc...
    2) $ make NOCACHE=yes DOCKERHUB=yes build-pynode-image
    3) $ make NOCACHE=yes DOCKERHUB=yes build-pulumi-image
    4) $ make NOCACHE=yes DOCKERHUB=yes build-awsmgr-image
    5) $ make NOCACHE=yes DOCKERHUB=yes build-vice-image

Note: Only recompile step 5 unless you need to modify the Python/NodeJS/AWS/Pulumi root alpine Image. Only takes ~1 minute

#### Simplify C&C of AWS resources

4 elements of project

  1) VICE applicaiton for Cyverse infrasturcture (cy-aws-vice)
  2) Lambda functions for AWS C&C
  3) Flask UX application for vice app



## Issues

  - using docker buildx sometimes uninstalls itself?
    $ apt install docker-buildx-plugin
    $ docker buildx install