#!/usr/bin/env python3

## requires:
# python 3.11 !!
# zip
#
import argparse
import json
import os
import pathlib
import pprint
import re

import subprocess
import sys
import tempfile
import time
import jmespath


from subprocess import CalledProcessError
from collections import namedtuple
from pathlib import Path
from dotmap import DotMap

from pylib.utils import ActiveState

"""
A minimal aws cli toolchain to setup/configure lambda stack without boto3
Note: Boto3 might be easier to do most of this, but assuming aws cli tools might be easier for end user.
"""

pp = pprint.PrettyPrinter(indent=4)
bin_path = Path(__file__).absolute().parent


class CommandExeception(CalledProcessError):
    pass


def zip_lambda_func(ast: dict):
    print("Ziping up lambda function")
    if ast.dm.paths.tmp_dir is None:
        return

    print(f"lambda_dir: {ast.dm.paths.lambda_func}")
    try:
        result = subprocess.run(
            [
                "zip", f"{ast.dm.paths.tmp_dir}/function.zip", ast.dm.paths.lambda_func
            ], cwd=ast.dm.paths.lambda_func_dir, capture_output=True, text=True, check=True,
        )
    except CalledProcessError as e:
        print("ERROR")
        print(e.stdout)
        print(e.stderr)
        raise e


def execute_cmd(
        ast: ActiveState, refkey: str = None, debug: bool = False,
        stdout: bool = False, fake: bool = False,
        skip_load_json: bool = False, output: str = 'json',
        shell = False
    ):
    """
    Given a command structure -> {'cmd': ["echo", "output"], 'value': 'lol'}
    """
    if refkey is None:
        raise Exception("Error: Must provide a refkey of the form 'section.element' from ini to run")

    instruction = ast.get_refkey(refkey)

    if(instruction is None):
        raise Exception(f"Error: section '{refkey}' is not in config!")
    elif(instruction is DotMap):
        instruction = instruction.toDict()

    if 'cmdline' not in instruction:
        raise Exception(f"Error: cmdline not in config: '{ast.config_file_path.name}' @ ({refkey})")

    cmdline = instruction['cmdline'] if 'cmdline' in instruction else []
    # This converts any lingering dictionaries into strings
    # cmdline = list(map(lambda x: json.dumps(x) if isinstance(x, dict) or isinstance(x, list) else x, cmdline))
    if not cmdline:
        return {}

    if 'capture' in instruction._map:
        capture = list(instruction._map['capture'])
    else:
        capture = []

    if ast.dm.general.awsprofile is not None:
        cmdline.extend(["--profile", ast.dm.general.awsprofile])
    if ast.dm.general.awsregion is not None:
        cmdline.extend(['--region', ast.dm.general.awsregion])
    if output:
        cmdline.extend(['--output', output])

    if debug or ast.dm.general.debug:
        print(f"execute_cmd() -- {' '.join(cmdline)}")
        if len(capture):
            for catch in capture:
                print(f"{catch}")

    try:
        condenced_cmd = f"""{' '.join(cmdline)}"""
        if debug or ast.dm.general.debug or fake:
            print(f">{condenced_cmd}<")
        if not fake:
            if not shell:
                result = subprocess.run(cmdline, capture_output=True, text=True, check=True, shell=shell)
            else:
                result = subprocess.run(' '.join(cmdline), capture_output=True, text=True, check=True, shell=shell)
        else:
            for elm in cmdline:
                print(elm)
            return {}
    except CalledProcessError as e:
        print(">>>>ERROR<<<<")
        print(e.cmd)
        print(e.stdout)
        print(e.stderr)
        raise CommandExeception(e.returncode, e.cmd, e.stdout, e.stderr)
    else:
        if result.returncode:
            print(f"Command line failed: '{' '.join(cmdline)}'")
            sys.exit(result.returncode)
        # ret_string = result.stdout.replace('\n', '').replace('\r', '') if result.stdout is not None else ''
        if result.stdout and not skip_load_json:
            if debug or ast.dm.general.debug or stdout:
                print(f">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n{result.stdout}<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n\n")
            result_json = json.loads(result.stdout)
            if debug or ast.dm.general.debug or stdout:
                pp.pprint(result_json)
        else:
            result_json = {}

        returnvals = {}
        for i, val in enumerate(capture, 1):
            if debug or ast.dm.general.debug:
                print(f"working on capture [{i}]")
            if(('dest' not in val) or (not val['dest'])):
                raise Exception(f"Missing capture element with dest in config element [{i}] in @ ({refkey})!")
            if debug or ast.dm.general.debug:
                print(f"using query: {val['query']}")
            if 'query' in val and val['query']:
                result_val = jmespath.search(val['query'], result_json)
            else:
                result_val = result_json
            if debug or ast.dm.general.debug or stdout:
                print(f"jmespath returned '{json.dumps(result_val)}' from query '{val['query']}'")
            if result_val:
                ast.set_refkey(val['dest'], result_val)
                returnvals[val['dest']] = result_val
        return returnvals


def get_api_account(ast: ActiveState, debug: bool = False):
    ## GET ACCOUT ID - SETS computed.account_id
    if debug or ast.dm.general.debug:
        print(f"get_api_account()")
    results = execute_cmd(ast, refkey='account_setup.get_account_id', debug=debug)
    if debug or ast.dm.general.debug:
        print("execute_cmd returned:")
        pp.pprint(results)
    account_id = ast.get_refkey('computed.account_id')
    if account_id is not None:
        print(f"account_id: {account_id}")
    else:
        print("ERROR: No account id found for this user")
        sys.exit(1)


def get_or_create_iam_lambda_assume_role(ast: ActiveState, debug: bool = False, stdout: bool = False):
    ## GET OR CREATES AssumeRole for lambda
    if debug or ast.dm.general.debug:
        print(f"get_or_create_iam_lambda_assume_role()")
    create_new_role = False
    ast.set_refkey('computed.iam_assume_role_policy_doc_string', json.dumps(ast.dm_computed.json_documents.lambda_assume_role_policy_doc.toDict()))
    print(f"Fetching role {ast.dm_computed.names.lambda_assume_role_name} from aws")
    try:
        results = execute_cmd(ast, refkey='lambda_setup.get_lambda_assume_role_01', debug=debug, stdout=stdout)
    except CommandExeception as e:
        if re.search('NoSuchEntity', e.stderr):
            print(f"Lambda Role '{ast.dm_computed.names.lambda_assume_role_name}' not found")
            create_new_role = True
        else:
            raise e
    if not create_new_role:
        print(f"Update Role '{results['computed.role_name']}' for lambda function.")
        results = execute_cmd(ast, refkey='lambda_setup.update_lambda_assume_role_02b', debug=debug, stdout=stdout)
    else:
        print(f"Creating Role '{ast.dm_computed.names.lambda_assume_role_name}' for lambda function")
        results = execute_cmd(ast, refkey='lambda_setup.create_lambda_assume_role_02', debug=debug, stdout=stdout)


def get_or_create_s3_bucket(ast: ActiveState, debug: bool = False, stdout: bool = False):
    ## GET OR CREATE S3 Bucket for Lambda funct
    print(f"Creating S3 Bucket {ast.dm_computed.names.s3_bucket_name} for Lambda function")
    create_new_bucket = False
    try:
        results = execute_cmd(ast, refkey='lambda_setup.get_s3_bucket_03', debug=debug, stdout=stdout)
    except CommandExeception as e:
        if re.search('404', e.stderr):
            print(f"Bucket {ast.dm_computed.names.s3_bucket_name} not found")
            create_new_bucket = True
        else:
            raise e
    else:
        print(f"S3 bucket {ast.dm_computed.names.s3_bucket_name} already exists!")
    if create_new_bucket:
        results = execute_cmd(ast, section='lambda_setup.create_s3_bucket_04', debug=debug, stdout=stdout, skip_load_json=True)

    zip_lambda_func(ast)
    if not os.path.exists(f"{ast.dm.paths.tmp_dir}/function.zip"):
        print("ERROR: couldn't zip function up!")
        sys.exit(1)


def get_or_setup_lambda_fun(ast: ActiveState, debug: bool = False, stdout: bool = False):
    create_new_lambda_func = False
    try:
        results = execute_cmd(ast, refkey='lambda_setup.get_lambda_func_05', debug=debug, stdout=stdout)
    except CommandExeception as e:
        if re.search('ResourceNotFoundException', e.stderr):
            print(f"Function {ast.dm_computed.names.lambda_fun_name} not found!")
            create_new_lambda_func = True

    ## Create Lambda function
    if(create_new_lambda_func):
        results = execute_cmd(ast, refkey='lambda_setup.create_lambda_func_06', debug=debug, stdout=stdout)
        if (('computed.lambda_name' in results) and results['computed.lambda_name']):
            print(f"Lambda function '{results['computed.lambda_name']}' created!")
        else:
            print(f"ERROR: Could not create lambda function '{results['computed.lambda_name']}'")
            sys.exit(1)
    else:
        print(f"Lambda function \"{results['computed.lambda_name']}\" already exists (UPDATING)")
        results = execute_cmd(ast, refkey='lambda_setup.update_lambda_func_06b', debug=debug, stdout=stdout)
        if (('computed.lambda_name' not in results) or not results['computed.lambda_name']):
            print(f"ERROR: Could not update lambda function {ast.dm_computed.names.lambda_fun_name}!")
            sys.exit(1)
        time.sleep(1)
        results = execute_cmd(ast, refkey='lambda_setup.update_lambda_func_cfg_06c', debug=debug, stdout=stdout)
        if (('computed.lambda_name' not in results) or not results['computed.lambda_name']):
            print(f"ERROR: Could not update lambda function config {ast.dm_computed.names.lambda_fun_name}!")
            sys.exit(1)


def setup_iam_bucket_policy(ast: ActiveState, debug: bool = False, stdout: bool = False):
    """
    Setup the S3 Bucket policy for lambda role
    """
    if debug or ast.dm.general.debug:
        print(f"setup_lambda_assume_role_policy()")
    ## Setup IAM policy
    ast.set_refkey('computed.iam_bucket_policy_doc_string', json.dumps(ast.dm_computed.json_documents.cy_awsmgr_bucket_policy_doc.toDict()))
    # @TODO: Fix this weird bug with aws cli not working without shell here?!?
    results = execute_cmd(ast, refkey='lambda_setup.query_lambda_iam_policy_06d', debug=debug, stdout=stdout, shell=True)
    if (('computed.policy_s3_name' not in results) or not results['computed.policy_s3_name']):
        print(f"Creating policy '{ast.dm_computed.names.lambda_bucket_pol_name}' for lambda")
        results = execute_cmd(ast, refkey='lambda_setup.create_lambda_iam_policy_06e', debug=debug, stdout=stdout)
        if (('computed.policy_s3_name' not in results) or not results['computed.policy_s3_name']):
            print(f"ERROR: Issue creating iam policy '{ast.dm_computed.names.lambda_bucket_pol_name}' for '{ast.dm_computed.names.lambda_fun_name}' lambda function!")
            sys.exit(1)
    else:
        print(f"Lambda function S3 Bucket IAM Policy '{ast.dm_computed.names.lambda_bucket_pol_name}' already exists!")


def setup_iam_logging_policy(ast: ActiveState, debug: bool = False, stdout: bool = False):
    """
    Setup the logging policy for Lambda role
    """
    ast.set_refkey('computed.iam_logging_policy_doc_string', json.dumps(ast.dm_computed.json_documents.cy_awsmgr_loggroup_policy_doc.toDict()))
    # @TODO: Fix this weird bug with aws cli not working without shell here?!?
    results = execute_cmd(ast, refkey='lambda_setup.query_lambda_iam_policy_06f', debug=False, stdout=False, shell=True)
    if (('computed.policy_log_name' not in results) or not results['computed.policy_log_name']):
        print(f"Creating policy '{ast.dm_computed.names.lambda_log_pol_name}' for lambda")
        results = execute_cmd(ast, refkey='lambda_setup.create_lambda_iam_policy_06g', debug=False, stdout=False)
        if (('computed.policy_log_name' not in results) or not results['computed.policy_log_name']):
            print(f"ERROR: Issue creating iam policy '{ast.dm_computed.names.lambda_log_pol_name}' for '{ast.dm_computed.names.lambda_fun_name}' lambda function!")
            sys.exit(1)
    else:
            print(f"Lambda function Log Bucket IAM Policy '{ast.dm_computed.names.lambda_log_pol_name}' already exists!")


def attach_policies_to_lambda_role(ast: ActiveState, debug: bool = False, stdout: bool = False):
    results = execute_cmd(ast, refkey='lambda_setup.list_lambda_attached_policies', debug=debug, stdout=stdout)
    larn = ast.dm_computed.names.lambda_assume_role_name
    lbpm = ast.dm_computed.names.lambda_bucket_pol_name
    llpn = ast.dm_computed.names.lambda_log_pol_name
    if results and 'computed.attached_polices' in results:
        attached_pols = results['computed.attached_polices']
        lbpm_attached = jmespath.search(f"[?PolicyName=='{lbpm}'].PolicyName|[0]", attached_pols)
        llpn_attached = jmespath.search(f"[?PolicyName=='{llpn}'].PolicyName|[0]", attached_pols)
    else:
        lbpm_attached = False
        llpn_attached = False

    if not lbpm_attached:
        print(f"Attaching IAM policy '{lbpm}' to role '{larn}'")
        results = execute_cmd(ast, refkey='lambda_setup.attach_iam_lambda_role_policy_7a', debug=debug, stdout=stdout)
    else:
        print(f"""IAM Policy '{lbpm}' is already attached to lambda role '{larn}'!""")

    if not llpn_attached:
        print(f"Attaching IAM policy '{llpn}' to role '{larn}'")
        results = execute_cmd(ast, refkey='lambda_setup.attach_iam_lambda_role_policy_7b', debug=debug, stdout=stdout)
    else:
        print(f"""IAM Policy '{llpn}' is already attached to lambda role '{larn}'!""")


def set_lambda_arn(ast: ActiveState, debug: bool = False, stdout: bool = False):
    ## Get Lambda ARN - SETS computed.lambda_arn
    # @TODO: Fix this weird bug with aws cli not working without shell here?!?
    results = execute_cmd(ast, refkey='lambda_setup.get_lambda_arn_01', debug=debug, stdout=stdout, shell=True)
    if results and 'computed.returned' in results:
        arns = results['computed.returned']
        if len(arns) == 1:
            lambda_arn = arns[0]
            print(f"Lambda ({ast.dm_computed.names.lambda_fun_name}) arn : {lambda_arn}")
            ast.set_refkey('computed.lambda_arn', lambda_arn)
        else:
            print(f"ERROR: Could not find arn for Lambda {ast.dm_computed.names.lambda_fun_name}")
            sys.exit(1)


def setup_gateway(ast: ActiveState, debug: bool = False, stdout: bool = False):
    if debug or ast.dm.general.debug:
        print(f"setup_gateway(gateway_name = {ast.dm_computed.names.api_gateway_name})")
    # @TODO: Fix this weird bug with aws cli not working without shell here?!?
    results = execute_cmd(ast, refkey='gateway_setup.check_gateway_00', debug=False, stdout=stdout, shell=True)
    if 'computed.rest_api_gateways' in results:
        rest_api_gateways = results['computed.rest_api_gateways']
    else:
        rest_api_gateways = []

    if( len(rest_api_gateways) > 1):
        print(f"ERROR: you have too many ({len(rest_api_gateways)}) duplicated gateways matching {ast.dm_computed.names.api_gateway_name}!")
        sys.exit(1)
    elif (len(rest_api_gateways) == 1):
        print(f"Gateway {ast.dm_computed.names.api_gateway_name} exists!")
        print(f"\t id: {rest_api_gateways[0]['id']}")
        ast.set_refkey('computed.rest_api_id', rest_api_gateways[0]['id'])
        ast.set_refkey('computed.root_resource_id', rest_api_gateways[0]['rootResourceId'])
    else:
        print("Create gateway...")
        results = execute_cmd(ast, refkey='gateway_setup.create_gateway_01', debug=debug, stdout=stdout)
        if 'computed.rest_api_gateway' in results:
            rest_api_gateway = results['computed.rest_api_gateway']
        else:
            rest_api_gateway = {}

        if(not rest_api_gateway):
            print(f"ERROR: Issue with creating gateway, nothing returned!")
            sys.exit(1)
        print(f"Gateway {ast.dm_computed.names.api_gateway_name} created!")
        print(f"\t id: {rest_api_gateway['id']}")
        ast.set_refkey('computed.rest_api_id', rest_api_gateway['id'])
        ast.set_refkey('computed.root_resource_id', rest_api_gateway['rootResourceId'])


def get_gateway_root_id(ast: ActiveState, debug: bool = False, stdout: bool = False):
    if debug or ast.dm.general.debug:
        print(f"get_gateway_root_id(gateway_name = {ast.dm_computed.names.api_gateway_name})")
    ## Step 2 : Get Root Resource ID
    results = execute_cmd(ast, refkey='gateway_setup.get_resource_id_02', debug=debug)
    if 'computed.returned' in results and results['computed.returned']:
        gw_resources = results['computed.returned']
        api_gw_root_ids = jmespath.search("items[?path == '/'].id", gw_resources)
        if len(api_gw_root_ids) != 1:
            pp.pprint(gw_resources)
            print("ERROR: did not find apigateway root id!")
        else:
            api_gw_root_id = api_gw_root_ids[0]
            ast.set_refkey('computed.gw_root_id', api_gw_root_id)
            print(f"API Gateway root(/) id : {api_gw_root_id}")

        api_gw_deadman_child = jmespath.search(f"items[?path == '/{ast.dm_computed.names.deadman_uri_path}']", gw_resources)
        if len(api_gw_deadman_child) == 1:
            api_gw_deadman_child_id = jmespath.search("id", api_gw_deadman_child[0])
            print(f"API Gateway child(/{ast.dm_computed.names.deadman_uri_path}) id : {api_gw_deadman_child_id}")
            ast.set_refkey('computed.deadman_child_id', api_gw_deadman_child_id)
            api_gw_deadman_methods = jmespath.search("resourceMethods", api_gw_deadman_child[0])
            print(f"API Gateway child(/{ast.dm_computed.names.deadman_uri_path}) methods : {api_gw_deadman_methods}")
            ast.set_refkey('computed.deadman_methods', api_gw_deadman_methods)


def create_uri_resources(ast: ActiveState, debug: bool = False, stdout: bool = False):
    ## Step 3 : Create gateway path resource, SETS computed.resouce_id
    if debug or ast.dm.general.debug:
        print(f"create_uri_resource(gateway_name = {ast.dm_computed.names.api_gateway_name}, path = {ast.dm_computed.names.deadman_uri_path})")
    if 'deadman_child_id' in ast.dm_computed.computed and ast.dm_computed.computed['deadman_child_id']:
        print(f"Resource {ast.dm_computed.names.deadman_uri_path} already exists! @ child_id = {ast.dm_computed.computed.deadman_child_id}")
    else:
        results = execute_cmd(ast, refkey='gateway_setup.create_resource_03', debug=True, stdout=stdout)
        if 'computed.returned' in results and results['computed.returned']:
            child_resource = results['computed.returned']
            api_gw_deadman_child_id = jmespath.search("id", child_resource)
            print(f"API Gateway child(/{ast.dm_computed.names.deadman_uri_path}) id : {api_gw_deadman_child_id}")
            ast.set_refkey('computed.deadman_child_id', api_gw_deadman_child_id)
            api_gw_deadman_methods = jmespath.search("resourceMethods", child_resource)
            print(f"API Gateway child(/{ast.dm_computed.names.deadman_uri_path}) methods : {api_gw_deadman_methods}")
            ast.set_refkey('computed.deadman_methods', api_gw_deadman_methods)


def add_method_to_resource(ast: ActiveState, debug: bool = False, stdout: bool = False):
    ## Step 4 : Create Method (using resource)
    if debug or ast.dm.general.debug:
        print(f"add_method_to_resource(gateway_name = {ast.dm_computed.names.api_gateway_name}, path = {ast.dm_computed.names.deadman_uri_path})")

    if not 'POST'in ast.dm_computed.computed.deadman_methods.toDict():
        execute_cmd(ast, refkey='gateway_setup.create_method_04', debug=debug, stdout=stdout)


def add_api_lambda_integration(ast: ActiveState, debug: bool = False, stdout: bool = False):
    ## Step 5 : Integrate method with the lambda (no results needed)
    if debug or ast.dm.general.debug:
        print(f"add_api_lambda_integration(gateway_name = {ast.dm_computed.names.api_gateway_name}, path = {ast.dm_computed.names.deadman_uri_path}, lambda_arn = {ast.dm_computed.computed.lambda_arn})")
    execute_cmd(ast, refkey='gateway_setup.associate_lambda_05', debug=debug, stdout=stdout)


def get_lambda_perm_policies(ast: ActiveState, debug: bool = False, stdout: bool = False):
    ## Step 6a : get existing permissions for lambda
    if debug or ast.dm.general.debug:
        print(f"get_lambda_perm_policies(lambda = {ast.dm_computed.names.lambda_fun_name})")
    results = execute_cmd(ast, refkey='gateway_setup.check_lambda_policy', debug=debug, stdout=stdout)
    if 'computed.returned' in results and results['computed.returned']:
        lambda_policies = results['computed.returned']
        return jmespath.search('Policy', lambda_policies)


def set_lambda_perm_policy(ast: ActiveState, debug: bool = False, stdout: bool = False):
    ## Step 6 : Grant api gateway permission to invoke lambda function (no results needed)
    if debug or ast.dm.general.debug:
        print(f"get_lambda_perm_policies(lambda = {ast.dm_computed.names.lambda_fun_name})")
    awsgateway_perm_exits = False
    pol = get_lambda_perm_policies(ast, debug=debug, stdout=stdout)
    if isinstance(pol, str):
        pol = json.loads(pol)
    sid_invoke_perm = jmespath.search("Statement[?Principal.Service == 'apigateway.amazonaws.com']", pol)

    if len(sid_invoke_perm) >= 1:
        awsgateway_perm_exits = True

    if not awsgateway_perm_exits:
        execute_cmd(ast, refkey='gateway_setup.setup_lambda_invoke_perm_06', debug=debug, stdout=stdout)
    else:
        print("Lambda awsgateway permission already exists")


def create_dev_deployment(ast: ActiveState, debug: bool = False, stdout: bool = False):
    results = execute_cmd(ast, refkey='gateway_setup.deploy_apigateway_07', debug=False, stdout=False)
    if 'computed.returned' in results and results['computed.returned']:
        aws_gw_child = results['computed.returned']
        print(aws_gw_child)


def setup_lambda_stack(ast: ActiveState):
    # create a local tmp directory

    # TODO: Fixes needed, if gateway id changes, must update lambda policy "apigateway-lambda-invoke"!

    path = pathlib.Path(ast.dm.paths.tmp_dir)
    path.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=ast.dm.paths.tmp_dir) as temp_dir:
        print(f"Temporary directory created at: {temp_dir}")
        get_api_account(ast, debug=False)
        get_or_create_iam_lambda_assume_role(ast, debug=False)
        get_or_create_s3_bucket(ast, debug=False)
        get_or_setup_lambda_fun(ast, debug=False)
        setup_iam_bucket_policy(ast, debug=False)
        setup_iam_logging_policy(ast, debug=False)
        attach_policies_to_lambda_role(ast, debug=False)
        set_lambda_arn(ast, debug=False)

        setup_gateway(ast, debug=False)
        get_gateway_root_id(ast, debug=False)
        create_uri_resources(ast, debug=False)
        add_method_to_resource(ast, debug=False)
        add_api_lambda_integration(ast, debug=False)
        set_lambda_perm_policy(ast, debug=False)
        create_dev_deployment(ast, debug=False)


def test_deadman_url(ast: ActiveState, debug: bool = False, stdout: bool = False):
    if debug or ast.dm.general.debug:
        print(f"test_deadman_url(lambda = {ast.dm_computed.names.lambda_fun_name} url = /{ast.dm_computed.names.deadman_uri_path})")
    get_api_account(ast, debug=False)
    setup_gateway(ast, debug=False)
    get_gateway_root_id(ast, debug=False)
    print(f"Using gateway id: {ast.dm_computed.computed.rest_api_id}")
    print(f"ENDPOINT: https://{ast.dm_computed.computed.rest_api_id}.execute-api.{ast.dm_computed.general.awsregion}.amazonaws.com/{ast.dm_computed.names.apigateway_stage}/")
    results = execute_cmd(ast, refkey='final.test_lambda_invoke', debug=False, stdout=False)
    ran_success = False
    if 'computed.returned' in results and results['computed.returned']:
        returned = results['computed.returned'] # http_test_success status
        if jmespath.search("status", returned) == 200:
            ran_success = True
    if ran_success:
        print("Successfully tested URL")
    else:
        print("Failed to test URL")

def main(ast: ActiveState, args: bool):
    """
    Create lambda function and api gateway
    """
    if args.setup_stack:
        setup_lambda_stack(ast)
    elif args.test_deadman:
        print("Testing...")
        test_deadman_url(ast)

    sys.exit(0)


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
    parser.add_argument(
        '--region', metavar='region', required=False, default=None,
        help='The AWS region used to execute cli commands'
    )
    parser.add_argument(
        '--setup-stack', action='store_true'
    )
    parser.add_argument(
        '--test-deadman', action='store_true'
    )
    args = parser.parse_args()
    if((args.config_path is not None)):
        ast = ActiveState(args.config_path)
    else:
        ast = ActiveState(bin_path / 'cyawsmgr_config.ini')
    if((args.profile is None) and ast.dm.general.awsprofile):
        profile = ast.dm.general.awsprofile
    elif((args.profile is None) and (not ast.dm.general.awsprofile)):
        parser.print_help()
        print("\nError: No default profile, use --profile <name>")
        sys.exit(1)
    else:
        profile = args.profile
    if((args.region is None) and ast.dm.general.awsregion):
        region = ast.dm.general.awsregion
    elif((args.region is None) and (not ast.dm.general.awsregion)):
        ## TODO Use environment?
        parser.print_help()
        print("\nError: No default region, use --region <name>")
        sys.exit(1)
    else:
        region = args.region
    main(ast, args)
