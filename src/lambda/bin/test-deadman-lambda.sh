#!/usr/bin/env bash

SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

echo "Testing Deadman Lambda w/ Bearer token auth...."
APIGATEWAY_ID=`aws apigateway get-rest-apis $@ | jq -r -c '.items[] | if .name == "cy-awsmgr-gateway" then .id else empty end'`
AUTH_TOKEN=`cat $(realpath $DIR/../src/token.txt) | tr -d '\n'`

if [[ -z $APIGATEWAY_ID ]] ; then
  echo "ERROR: APIGATEWAY_ID is empty! Try passing --profile <awsusername> --region <region>"
  exit 1
fi

if [[ -z $AUTH_TOKEN ]]; then
  echo "ERROR: AUTH_TOKEN is empty! Might be an issue with token.txt file..."
  exit 1
fi

AUTH_TOKEN='bad'

echo "APIGATEWAY_ID = $APIGATEWAY_ID"
echo "   AUTH_TOKEN = $AUTH_TOKEN"

curl -X POST https://$APIGATEWAY_ID.execute-api.us-west-2.amazonaws.com/dev/deadman -H "Authorization: $AUTH_TOKEN" -H "Content-Type: application/json"