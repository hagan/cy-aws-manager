#!/bin/bash

if [ -z "$1" ]; then
  filename='config.mk'
else
  filename=$1
fi

if ! test -f $filename; then
  echo "Error missing '$filename'!"
  exit 1
fi

if [ -z "${GITHUB_OUTPUT}" ]; then
  DEBUG_OUTPUT=true
fi

## Output the makefile config/settings/etc...
# make -f Makefile -n -p | awk '!/^#/ && NF'

ENV_VARS=( \
  $(awk -F'[[:space:]]*[:?]?=' '/^[^#]/ && NF>1 {print $1}' $filename | \
    tr '\n' ' ') \
  )

for elm in "${ENV_VARS[@]}"; do
  elm_val=$( \
    make -f Makefile --include $filename -p -n | \
    grep "^$elm.*=" | \
    awk -F'[[:space:]]*=[[:space:]]*' '{print $NF}' \
  )
  if [[ "$DEBUG_OUTPUT" == "true" ]]; then
    echo "DEBUG: ${elm}=${elm_val}"
  else
    declare $elm=$elm_val
    export $elm
    ## deprecated set-out -> now just pipe it
    # echo "::set-output name=$elm::$elm_val"
    echo "${elm}=${elm_val}" >> $GITHUB_OUTPUT
  fi
done
