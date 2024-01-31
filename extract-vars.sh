#!/bin/bash

# Exports variables for a Makefile configuration (config.mk)
if [ -z "$1" ]; then
    echo "Usage: $0 filename"
    exit 1
fi

ENV_VARS=($(awk '!/^#/ && NF' $1 | awk -F '[ =]' '{if (NF > 0) print $1}' | tr '\n' ' '))

for elm in "${ENV_VARS[@]}"; do
  elm_val=$(make -f Makefile --include config.mk -p -n | grep "^$elm.*=")
  declare "$elm=$elm_val"
  export "$elm"
  echo "::set-output name=$elm::$elm_val"
done
