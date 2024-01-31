#!/bin/bash

# Exports variables for a Makefile configuration (config.mk)

# TODO: need to remove quotes (" & ') from Vars? maybe...
if [ -z "$1" ]; then
    echo "Usage: $0 filename"
    exit 1
fi

if [ "x${GITHUB_OUTPUT}" == "x" ]; then
  GITHUB_OUTPUT=/dev/null
fi

ENV_VARS=($(awk '!/^#/ && NF' $1 | awk -F '[ =]' '{if (NF > 0) print $1}' | tr '\n' ' '))

for elm in "${ENV_VARS[@]}"; do
  elm_val=$(make -f Makefile --include config.mk -p -n | grep "^$elm.*=" | awk -F'=' '{ gsub(/^[ \t]+/, "", $2); print $2 }')
  declare "$elm=$elm_val"
  export "$elm"
  ## deprecated set-out -> now just pipe it
  # echo "::set-output name=$elm::$elm_val"
  echo "${elm}=${elm_val}" >> $GITHUB_OUTPUT
done
