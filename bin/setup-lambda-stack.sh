#!/usr/bin/env bash

LAMBDA_ROLE='lambda-ex'
LAMBDA_POLICY='{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}'

function ask_yes_or_no() {
  read -p "$1 ([y]es or [N]o): "
  case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
    y|yes) echo "yes" ;;
    *)     echo "no" ;;
  esac
}

function main() {
  echo "This will use your admin level credentials on aws cli and stand up a lambda function"
  if [[ "no" == $(ask_yes_or_no "Are you sure?") || \
    "no" == $(ask_yes_or_no "Are you *really* sure?") ]]
  then
    echo "Abort"
    exit 0
  else
    echo "Do scary thing"
    if ! aws sts get-caller-identity; then
      >&2 echo "ERROR: credentials expired? try using --profile <username>"
      exit 1
    fi
    aws iam get-role --role-name "$LAMBDA_ROLE"
    # if aws iam get-role --role-name "$LAMBDA_ROLE" > /dev/null 2>&1; then
    #   echo "Role '$LAMBDA_ROLE' exists."
    # else
    #   echo "Role '$LAMBDA_ROLE' does *not* exists."
    #   # aws iam create-role \
    #   #   --role-name ${LAMBDA_ROLE} \
    #   #   --assume-role-policy-document ${LAMBDA_POLICY}
    # fi
  fi
}

main "$@"