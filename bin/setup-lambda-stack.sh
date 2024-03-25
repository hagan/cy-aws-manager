#!/usr/bin/env bash

SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

function ask_yes_or_no() {
  read -p "$1 ([y]es or [N]o): "
  case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
    y|yes) echo "yes" ;;
    *)     echo "no" ;;
  esac
}


S3_BUCKET_NAME='cy-awsmgr-bucket'
LAMBDA_FUN_NAME='SaveDateTimeToS3'
LAMBDA_ROLE='lambda-ex'
LAMBDA_POLICY='{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}'
S3_ALLOW_LAMBDA_POL="{\"Version\": \"2012-10-17\",\"Statement\": [{\"Effect\": \"Allow\",\"Action\": [\"s3:GetObject\",\"s3:PutObject\"],\"Resource\": \"arn:aws:s3:::$S3_BUCKET_NAME}/*\"}]}"
TMP_DIR=${HOME}/tmp
LAMBDA_UPDATE_POLL_FUNC_DIR=$(realpath "${DIR}/../src/lambda")
LAMBDA_UPDATE_POLL_FUNC_PATH="$LAMBDA_UPDATE_POLL_FUNC_DIR/lambda_function.py"



if [[ -z $HOME ]]; then
  >&2 echo "ERROR: HOME is not available!"
elif [[ ! -z $HOME ]] && [[ ! -d $HOME/tmp ]]; then
  if [[ "no" == $(ask_yes_or_no "Create $HOME/tmp directory?") ]]; then
    echo "Creating directory $HOME/tmp"
    mkdir -p $HOME/tmp
  fi
fi

function get_account_id() {
  ACCOUNT_ID=$(aws sts get-caller-identity "$@" | jq '.Account' | tr -d '"')
  if [[ -z $ACCOUNT_ID ]]; then
    >&2 echo "ERROR: credentials expired? try using --profile <username>"
    exit 1
  fi
  echo $ACCOUNT_ID
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
    ACCOUNT_ID=$(get_account_id "$@")


    EXISTING_ROLENAME=$(aws iam get-role --role-name "$LAMBDA_ROLE" "$@" 2> /dev/null | jq -r -c '.Role.RoleName' | tr -d '"')
    if [[ ! -z ${EXISTING_ROLENAME} ]]; then
      echo "Role '$EXISTING_ROLENAME' exists."
    else
      echo "Role '$LAMBDA_ROLE' does *not* exists."
      CREATED_ROLENAME=$(aws iam create-role \
        --role-name ${LAMBDA_ROLE} \
        --assume-role-policy-document "${LAMBDA_POLICY}" "$@" 2> /dev/null \
        | jq -r -c '.Role.RoleName'\
        | tr -d '"' \
      )
      if [[ ! -z ${CREATED_ROLENAME} ]]; then
        echo "Created Role: ${CREATED_ROLENAME}"
      else
        >&2 echo "ERROR: Failed to create role."
        exit 1
      fi
    fi
    ## Now we have a role 'lambda-ex' that can auth as lambda, need to create S3 bucket
    set +e
    if [[ ! -z ${S3_BUCKET_NAME} ]]; then
      ISBUCKET=$(aws s3api head-bucket --bucket ${S3_BUCKET_NAME} "$@" 2> /dev/null)
    fi
    set -e
    if [[ -z ${ISBUCKET} ]]; then
      echo "Creating bucket ${S3_BUCKET_NAME}..."
      aws s3 mb s3://${S3_BUCKET_NAME} "$@"
    else
      echo "Bucket ${S3_BUCKET_NAME} already exists"
    fi
    ## ZIP UP FUNCTION!
    echo "Ziping up lambda function"
    (cd $LAMBDA_UPDATE_POLL_FUNC_DIR; zip ${TMP_DIR}/function.zip lambda_function.py)
    if [[ ! -f ${TMP_DIR}/function.zip ]]; then
      >&2 echo "ERROR: Could not compress lambda function"
      exit 1
    fi

    ISLAMBDA=$(aws lambda get-function --function-name $LAMBDA_FUN_NAME "$@" | jq -r -c '.Configuration.FunctionName')
    if [[ $ISLAMBDA == "$LAMBDA_FUN_NAME" ]]; then
      echo "The function '$LAMBDA_FUN_NAME' already exists, updating"
      aws lambda update-function-code --function-name $LAMBDA_FUN_NAME --zip-file fileb://${TMP_DIR}/function.zip "$@"
    else
      echo "New lambda function '$LAMBDA_FUN_NAME' added to aws"
      aws lambda create-function --function-name $LAMBDA_FUN_NAME \
        --zip-file fileb://${TMP_DIR}/function.zip --handler lambda_function.lambda_handler \
        --runtime python3.11 --role arn:aws:iam::${ACCOUNT_ID}:role/${LAMBDA_ROLE} "$@"
    fi


    # Create S3 Allow Policy for Lambda role..

    aws iam create-policy --policy-name cy-awsmgr-allow-lambda-s3 --policy-document "${S3_ALLOW_LAMBDA_POL}" "$@"
    # CREATED_POL=$(aws iam create-policy --policy-name cy-awsmgr-allow-lambda-s3 --policy-document ${S3_ALLOW_LAMBDA_POL} )

  fi
}

main "$@"