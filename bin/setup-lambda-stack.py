#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import pprint
import re
import subprocess
import sys
import tempfile
import tomllib  ## install this

from subprocess import CalledProcessError

"""
A minimal aws cli toolchain to setup/configure lambda stack without boto3
"""

pp = pprint.PrettyPrinter(indent=4)
bin_path = os.path.dirname(os.path.realpath(__file__))


def expand_string(input_str: str, **variables: dict) -> str:
    """
    Takes as input a string with tokens i.e.
    "This is a test message on {{ vardate }}. Hi {{ name }}, how are you?",
    **{'vardate': 'Jan 01, 1990', 'name': 'John'}
    results in This is a test message on Jan 01, 1990. Hi John, how are you?"
    """
    compiled_pattern = re.compile(r'(\{\{\s*\w+\s*\}\})')
    split_result1 = [seg for seg in compiled_pattern.split(input_str) if seg]
    split_result2 = []
    for seg in split_result1:
        match = re.match(r"\{\{\s*(\w+)\s*\}\}", seg)
        if match and match.group(1) in variables:
            split_result2.append(variables[match.group(1)])
        elif match and match.group(1) in os.environ:
            split_result2.append(os.environ[match.group(1)])
        else:
            split_result2.append(seg)

    return ''.join([str(elm) for elm in split_result2])


def expand_variables(unresolved_vars: dict, resolved_vars: dict = {}, level=0, max=10) -> dict:
    """
    Takes a dictionary of variables and expands {% var %}
    """
    # print(f"expand_variables(level={level})")
    if not unresolved_vars:
        return resolved_vars

    token_pattern = r"\{\{\s*(\w+)\s*\}\}"
    del_list = []
    for key, val in unresolved_vars.items():
        if(type(val) is str):
            matches = re.findall(token_pattern, val)
            if not matches:
                # No tokens, fully resolved
                resolved_vars[key] = val
                del_list.append(key)
            else:
                # This has a token, expand string
                ret_value = expand_string(val, **resolved_vars)
                # Check result if fully resolved?
                matches = re.findall(token_pattern, ret_value)
                if not matches:
                    resolved_vars[key] = ret_value
                    del_list.append(key)
                else:
                    unresolved_vars[key] = ret_value
        else:
            resolved_vars[key] = val
            del_list.append(key)

    for key in del_list:
        del unresolved_vars[key]

    if level >= max:
        print(f"WARNING Max depth {level} reached!")
        return resolved_vars
    return expand_variables(unresolved_vars, resolved_vars, level=level+1)


def load_config(config_file_path: str = None):
    """
    Read in our "cyawsmgr_config.ini" and fill in missing variables
    """
    if config_file_path is None:
        config_file_path = os.path.join(bin_path, 'cyawsmgr_config.ini')
    config = {
        'general': {}
    }
    resolve_vars = {}
    data = {}
    if os.path.exists(config_file_path):
        with open(config_file_path, 'rb') as file:
            data = tomllib.load(file)
            for key, group in data.items():
                if(type(group) is not dict):
                    resolve_vars[key] = group
                elif (type(group) is dict):
                    for subkey, value in group.items():
                        resolve_vars[subkey] = value
                else:
                    raise Exception(f"'{type(group)}' unexpected type on group issue..")
            resolved_vars = expand_variables(resolve_vars)
            for key, group in data.items():
                if((type(group) is not dict) and key in resolved_vars.keys()):
                    config['general'][key] = resolved_vars[key]
                elif((type(group) is not dict) and (key not in resolved_vars.keys())):
                    raise Exception("Error: Key '{key}' was not found in your ini config")
                elif (type(group) is dict):
                    if key not in config:
                        config[key] = {}
                    for subkey, value in group.items():
                        if subkey in resolved_vars.keys():
                            config[key][subkey] = resolved_vars[subkey]
                        else:
                            raise Exception("Error: Key '{subkey}' was not found in your ini config")

            ## expand docs into dictionaries
            if 'json_documents' in config:
                for key, docs in config['json_documents'].items():
                    if type(docs) is str:
                        config['json_documents'][key] = json.loads(docs)
    else:
        raise Exception(f"ERROR no config file {config_file_path}")

    return config


def get_account_id(profile: str = 'default') -> str:
    """
    Us
    """
    result = subprocess.run(["aws", "sts", "get-caller-identity", "--profile", profile], capture_output=True, text=True, check=True)
    if result.returncode == 0 and result.stdout:
        datadict = json.loads(result.stdout)
        if 'Account' in datadict:
            return datadict['Account']
    else:
        print("ERROR: no account id!")
        sys.exit(1)


def query_policy(policy_name: str = None, profile: str = 'default') -> str:
    """
    aws iam list-policies --scope Local --query 'Policies[?PolicyName==`YourPolicyName`]'
    """
    if policy_name is None:
        return []
    try:
        result = subprocess.run(
            [
                "aws", "iam", "list-policies", "--scope", "Local", "--query",
                f"Policies[?PolicyName=='{policy_name}']", "--profile",
                profile
            ], capture_output=True, text=True, check=True
        )
    except CalledProcessError as e:
        print(e.stderr)
        raise e
    else:
        return json.loads(result.stdout)


def get_role(profile: str = 'default', role_name: str = None) -> str:
    """
    Get role if exists
    """
    if role_name is None:
        return
    try:
        result = subprocess.run(
            [
                "aws", "iam", "get-role", "--role-name", role_name, "--profile",
                profile
            ], capture_output=True, text=True, check=True
        )
    except CalledProcessError as e:
        if 'NoSuchEntity' in e.stderr:
            return {}
        else:
            print(e.stderr)
            raise e
    else:
        datadict = json.loads(result.stdout)
        if (
            ('Role' in datadict) and
            ('RoleName' in datadict['Role']) and
            (datadict['Role']['RoleName'] == role_name)
        ):
            return datadict['Role']['RoleName']


def create_role(profile: str = 'default', role_name: str = None, policy_doc: dict = {}) -> str:
    """
    Create a role from a policy doc
    """
    if role_name is None:
        return None
    try:
        result = subprocess.run(
            [
                "aws", "iam", "create-role",
                "--role-name", role_name,
                "--assume-role-policy-document", json.dumps(policy_doc),
                "--profile", profile
            ], capture_output=True, text=True, check=True
        )
        if result.returncode == 0 and result.stdout:
            print(result.stdout)
        else:
            print(result.stderr)
    except CalledProcessError as e:
        print(e.stderr)
        raise e
    else:
        datadict = json.loads(result.stdout)
        if (
            ('Role' in datadict) and
            ('RoleName' in datadict['Role']) and
            (datadict['Role']['RoleName'] == role_name)
        ):
            print(f"created role {role_name}")
            return datadict['Role']['RoleName']


def is_s3_bucket(profile: str = 'default', bucket_name: str = None):
    """
    Retrieves ARN from aws for s3 bucket?
    """
    if bucket_name is None:
        return
    try:
        result = subprocess.run(
            [
                "aws", "s3api", "head-bucket", "--bucket", bucket_name,
                "--profile", profile
            ], capture_output=True, text=True, check=True
        )
    except CalledProcessError as e:
        ## weird bug that on occasion raised e even though it returned a result it exists?
        datadict = json.loads(result.stdout)
        if 'BucketRegion' in datadict:
            return True
        else:
            print(e.stderr)
            raise e
    else:
        datadict = json.loads(result.stdout)
        if 'BucketRegion' in datadict:
            return True
        return False


def create_s3_bucket(profile: str = 'default', bucket_name: str = None):
    if bucket_name is None:
        return
    try:
        result = subprocess.run(
            [
                "aws", "s3", "mb", f"s3://{bucket_name}", "--profile", profile
            ], capture_output=True, text=True, check=True
        )
    except CalledProcessError as e:
        print("ERROR")
        print(e.stdout)
        print(e.stderr)
    else:
        pass


def zip_lambda_func(config: dict, profile: str = 'default', temp_dir: str = None):
    print("Ziping up lambda function")
    if temp_dir is None:
        return
    lambda_dir = config['paths']['lambda_dir']
    lambda_func = config['paths']['lambda_func']
    try:
        result = subprocess.run(
            [
                "zip", f"{temp_dir}/function.zip", lambda_func
            ], cwd=lambda_dir, capture_output=True, text=True, check=True,
        )
    except CalledProcessError as e:
        print("ERROR")
        print(e.stdout)
        print(e.stderr)
        raise e


def is_lambda_func(config: dict, profile: str = 'default', temp_dir: str = None):
    # ISLAMBDA=$(aws lambda get-function --function-name $LAMBDA_FUN_NAME "$@" | jq -r -c '.Configuration.FunctionName')
    lambda_fun_name = config['names']['lambda_fun_name']
    try:
        result = subprocess.run(
            [
                "aws", "lambda", "get-function", "--function-name", lambda_fun_name, "--profile", profile
            ], capture_output=True, text=True, check=True,
        )
    except CalledProcessError as e:
        print("ERROR")
        print(e.stdout)
        print(e.stderr)
        raise e
    else:
        datadict = json.loads(result.stdout)
        if(
            ('Configuration' in datadict) and
            ('FunctionName' in datadict['Configuration']) and
            (datadict['Configuration']['FunctionName'] == lambda_fun_name)
        ):

            return True
        return False


def update_lambda_func(config: dict, profile: str = 'default', temp_dir: str = None):
    if temp_dir is None:
        return
    print("updating lamda function")
    lambda_fun_name = config['names']['lambda_fun_name']
    try:
        result = subprocess.run(
            [
                "aws", "lambda", "update-function-code", "--function-name",
                lambda_fun_name, "--zip-file", f"fileb://{temp_dir}/function.zip",
                "--profile", profile
            ], capture_output=True, text=True, check=True,
        )
    except CalledProcessError as e:
        print("ERROR")
        print(e.stdout)
        print(e.stderr)
        raise e

def create_lambda_func(
        config: dict,
        profile: str = 'default',
        temp_dir: str = None,
        account_id: str = None,
        lambda_role: str = None
    ):
    if temp_dir is None or account_id is None or lambda_role is None:
        return

    #   --runtime python3.11 --role arn:aws:iam::${ACCOUNT_ID}:role/${LAMBDA_ROLE} "$@"
    print("Creating lamda function")
    lambda_fun_name = config['names']['lambda_fun_name']
    try:
        result = subprocess.run(
            [
                "aws", "lambda", "create-function", "--function-name",
                lambda_fun_name, "--zip-file", f"fileb://{temp_dir}/function.zip",
                "--handler", "lambda_function.lambda_handler",
                "--runtime", "python3.11", "--role", f"arn:aws:iam::{account_id}:role/${lambda_role}"
                "--profile", profile
            ], capture_output=True, text=True, check=True,
        )
    except CalledProcessError as e:
        print("ERROR")
        print(e.stdout)
        print(e.stderr)
        raise e


def create_lambda_policy(config: dict, profile: str = 'default', policy_name: str = None):
    """
    Create a policy document for our lambda func and S3
    """
    try:
        result = subprocess.run(
            [
                "aws", "iam", "create-policy", "--policy-name", policy_name,
                "--policy-document", json.dumps(config['json_documents'][policy_name]),
                "--profile", profile
            ], capture_output=True, text=True, check=True,
        )
    except CalledProcessError as e:
        print("ERROR")
        print(e.stdout)
        print(e.stderr)
        raise e


def main(config:dict, profile:str = None):
    # create a local tmp directory
    path = pathlib.Path(config['paths']['tmp_dir'])
    path.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(dir=config['paths']['tmp_dir']) as temp_dir:
        print(f"Temporary directory created at: {temp_dir}")

        account_id = get_account_id(profile=profile)
        print(f"account_id: {account_id}")

        print(f"Fetching role {config['names']['lambda_role']} from aws")
        lambda_role = get_role(profile=profile, role_name=config['names']['lambda_role'])
        if lambda_role:
            print(f"Role '{config['names']['lambda_role']}' exists.")
        else:
            lambda_role = create_role(
                profile=profile,
                role_name=config['names']['lambda_role'],
                policy_doc=config['json_documents']['lambda_policy_doc']
            )
            pp.pprint(lambda_role)

        # Create S3 bucket to stash results into
        bucket_name = config['names']['s3_bucket_name']
        print(is_s3_bucket(profile=profile, bucket_name=bucket_name))
        if(not is_s3_bucket(profile=profile, bucket_name=bucket_name)):
            create_s3_bucket(profile=profile, bucket_name=bucket_name)
        else:
            print(f"Yes, {bucket_name} bucket exists!")

        zip_lambda_func(config, profile=profile, temp_dir=temp_dir)
        if not os.path.exists(f"{temp_dir}/function.zip"):
            print("ERROR: couldn't zip function up!")
            sys.exit(1)

        if(not is_lambda_func(config, profile=profile, temp_dir=temp_dir)):
            create_lambda_func(config, profile=profile, temp_dir=temp_dir, account_id=account_id, lambda_role=lambda_role)
        else:
            update_lambda_func(config, profile=profile, temp_dir=temp_dir)

        matching_pols = query_policy(policy_name='cy-awsmgr-allow-lambda-s3', profile=profile)
        if any(['PolicyName' in x for x in matching_pols]):
            print("Policy exists")
        else:
            create_lambda_policy(config, profile=profile, policy_name='cy-awsmgr-allow-lambda-s3')


if __name__=="__main__":
    parser = argparse.ArgumentParser(description='Create a ArcHydro schema')
    parser.add_argument(
        '--config-path', metavar='file-path', required=False, default=None,
        help='Path to the app configuration file.'
    )
    parser.add_argument(
        '--profile', metavar='name', required=False, default=None,
        help='The AWS profile used to execute cli commands'
    )
    args = parser.parse_args()
    config = load_config(config_file_path=args.config_path)
    if((args.profile is None) and ('awsprofile' in config['general'])):
        profile = config['general']['awsprofile']
    elif((args.profile is None) and ('awsprofile' not in config['general'])):
        parser.print_help()
        print("\nError: No default profile, use --profile <name>")
    else:
        profile = args.profile
    main(config, profile=profile)