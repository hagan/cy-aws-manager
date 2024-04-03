#!/usr/bin/env bash

SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

echo "Testing Lambda w/ API KEY auth...."
if [[ ! -z ${AWS_PROFILE} ]] && [[ $# -eq 0 ]]; then
  ## keys are probably expired, just use the local profile if available
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SESSION_TOKEN
  unset AWS_CREDENTIAL_EXPIRATION
fi

if [[ -z ${APIGATEWAY_NAME} ]]; then
  APIGATEWAY_NAME='cy-awsmgr-gateway'
fi

if [[ -z ${APIGATEWAY_API_KEY_NAME} ]]; then
  APIGATEWAY_API_KEY_NAME='VICE_DEMO_ACCESSKEY'
fi

APIGATEWAY_ID=$(aws apigateway get-rest-apis $@ | jq -r -c ".items[] | if .name == \"${APIGATEWAY_NAME}\" then .id else empty end")

if [[ -z $APIGATEWAY_ID ]] ; then
   echo "ERROR: APIGATEWAY_ID returned empty! Try passing --profile <awsusername> --region <region>"
   exit 1
else
  echo "APIGATEWAY_ID: ${APIGATEWAY_ID}"
fi

APIKEY_ID=$(aws apigateway get-api-keys --name-query "${APIGATEWAY_API_KEY_NAME}" $@ | jq -r -c '.items[0].id')

if [[ -z $APIKEY_ID ]] ; then
   echo "ERROR: APIKEY_ID returned is empty!"
   exit 1
else
  echo "APIKEY_ID: ${APIKEY_ID}"
fi

if [ -z ${APIKEY_VALUE} ]; then
  AWSKEY_RAW=$(aws apigateway get-api-key --api-key $APIKEY_ID --include-value $@)
  if [[ $? -eq 0 ]]; then
    APIKEY_VALUE=$(echo $AWSKEY_RAW | jq -r -c '.value')
    APIKEY_NAME=$(echo $AWSKEY_RAW | jq -r -c '.name')
    echo "APIKEY_VALUE = ${APIKEY_VALUE}"
    echo "APIKEY_NAME = ${APIKEY_NAME}"
  fi
else
  echo "APIKEY_VALUE set as environment variable ${APIKEY_VALUE}"
fi
echo "curl -X POST https://$APIGATEWAY_ID.execute-api.us-west-2.amazonaws.com/dev/deadman -H \"x-api-key: ${APIKEY_VALUE}\" -H \"Content-Type: application/json\""
curl -X POST https://$APIGATEWAY_ID.execute-api.us-west-2.amazonaws.com/dev/deadman -H "x-api-key: ${APIKEY_VALUE}" -H "Content-Type: application/json"
