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
import jwt
import datetime
import secrets

import subprocess
import sys
import tempfile
import time
import jmespath
import logging
import zipfile

from subprocess import CalledProcessError
from collections import namedtuple
from pathlib import Path
from dotmap import DotMap

from pylib.utils import ActiveState

from colorama import init, Fore, Style

"""
A minimal aws cli toolchain to setup/configure lambda stack without boto3
Note: Boto3 might be easier to do most of this, but assuming aws cli tools might be easier for end user.
"""

pp = pprint.PrettyPrinter(indent=4)
bin_path = Path(__file__).absolute().parent
init(autoreset=True)
logging.basicConfig(
    filename='setup-lambda-stack.log',
    filemode='a',
    format='%(asctime)s,%(msecs)d %(name)s %(levelname)s %(message)s',
    datefmt='%H:%M:%S',
    level=logging.DEBUG
)
logger = logging.getLogger('awshackylambda')


class CommandExeception(CalledProcessError):
    pass


def log_msg(message: str, print_msg: bool, start_of_function: bool = True):
    if print_msg and start_of_function:
        print(f"{Fore.GREEN}{message}")
    else:
        print(message)
    logger.info(message)


def zip_lambda_func(ast: dict, debug: bool = False, stdout: bool = False, info: bool = False):
    """
    Generate secret and package lambda function
    """
    log_msg(f"zip_lambda_func(path={ast.dm.paths.lambda_func_dir})", info or ast.dm.general.info)

    if ast.dm.paths.tmp_dir is None:
        return

    lambda_code_path = Path(ast.dm.paths.lambda_func_dir)
    print(f"lambda code path: {lambda_code_path}")
    files = lambda_code_path.glob('*')

    token = secrets.token_urlsafe(64)
    with open(f'{ast.dm.paths.lambda_func_dir}/token.txt', 'w') as file:
        file.write(token)

    ## maybe use a py lib instead?
    with zipfile.ZipFile(f'{ast.dm.paths.tmp_dir}/function.zip', 'w') as zip_ref:
        for file in files:
            print(f"adding {file.name}")
            zip_ref.write(file, arcname=file.name)


def execute_cmd(
        ast: ActiveState, refkey: str = None, debug: bool = False,
        stdout: bool = False, info: bool = False, fake: bool = False,
        skip_load_json: bool = False, output: str = 'json',
        shell = False
    ):
    """
    Given a command structure -> {'cmd': ["echo", "output"], 'value': 'lol'}
    """
    log_msg(f"execute_cmd(refkey={refkey})", info or ast.dm.general.info)

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
        logger.error(f"command line: {e.cmd}")
        logger.error(f"retcode: {e.returncode}")
        logger.error(e.stdout)
        logger.error(e.stderr)
        raise CommandExeception(e.returncode, e.cmd, e.stdout, e.stderr)
    else:
        if result.returncode:
            print(f"Command line failed: '{' '.join(cmdline)}'")
            sys.exit(result.returncode)
        # ret_string = result.stdout.replace('\n', '').replace('\r', '') if result.stdout is not None else ''
        if result.stdout and not skip_load_json:
            if debug or ast.dm.general.debug or stdout:
                print(f"{Style.DIM}{result.stdout}<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n\n")
            else:
                logger.info(result.stdout)
            result_json = json.loads(result.stdout)
        else:
            result_json = {}

        returnvals = {}
        for i, val in enumerate(capture, 1):
            if debug or ast.dm.general.debug:
                print(f"working on capture [{i}]")
            if(('dest' not in val) or (not val['dest'])):
                raise Exception(f"Missing capture element with dest in config element [{i}] in @ ({refkey})!")
            dest = val['dest'] if 'dest' in val and val['dest'] else 'computed.returned'
            if debug or ast.dm.general.debug:
                print(f"using query: {val['query']}")
            if 'query' in val and val['query']:
                result_val = jmespath.search(val['query'], result_json)
            else:
                result_val = result_json
            if debug or ast.dm.general.debug or stdout:
                print(f"{Style.DIM}jmespath returned '{json.dumps(result_val)}' from query '{val['query']}'")
            if result_val:
                ast.set_refkey(dest, result_val)
                returnvals[dest] = result_val
        return returnvals


def package_lambdas(ast: ActiveState, debug: bool = True, stdout: bool = True):
    """
    Zip all lambdas for this deployment
    """
    zip_lambda_func(ast)
    if not os.path.exists(f"{ast.dm.paths.tmp_dir}/function.zip"):
        print("ERROR: couldn't zip function up!")
        sys.exit(1)


def get_api_account(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    ## GET ACCOUT ID - SETS computed.account_id
    log_msg("get_api_account()", ast.dm.general.info)
    results = execute_cmd(ast, refkey='account_setup.get_account_id', debug=debug, stdout=stdout, info=info)
    if debug or ast.dm.general.debug:
        info.logging(pp.pformat(results))
    account_id = ast.get_refkey('computed.account_id')
    if account_id is not None:
        print(f"{Style.BRIGHT}{Fore.BLUE}\taccount_id: {account_id}")
    else:
        print(f"{Fore.LIGHTRED_EX}ERROR: No account id found for this user")
        sys.exit(1)


def get_or_create_iam_lambda_assume_role(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    ## GET OR CREATES AssumeRole for lambda
    log_msg("get_or_create_iam_lambda_assume_role()", info or ast.dm.general.info)
    create_new_role = False
    ast.set_refkey('computed.iam_assume_role_policy_doc_string', json.dumps(ast.dm_computed.json_documents.lambda_assume_role_policy_doc.toDict()))
    print(f"\tFetching role {ast.dm_computed.names.lambda_assume_role_name} from aws")
    try:
        results = execute_cmd(ast, refkey='lambda_setup.get_lambda_assume_role_01', debug=debug, stdout=stdout, info=info)
    except CommandExeception as e:
        if re.search('NoSuchEntity', e.stderr):
            print(f"{Fore.YELLOW}Lambda Role '{ast.dm_computed.names.lambda_assume_role_name}' not found")
            create_new_role = True
        else:
            raise e
    if not create_new_role:
        print(f"\tUpdate Role '{results['computed.role_name']}' for lambda function.")
        results = execute_cmd(ast, refkey='lambda_setup.update_lambda_assume_role_02b', debug=debug, stdout=stdout, info=info)
    else:
        print(f"\tCreating Role '{ast.dm_computed.names.lambda_assume_role_name}' for lambda function")
        results = execute_cmd(ast, refkey='lambda_setup.create_lambda_assume_role_02', debug=debug, stdout=stdout, info=info)
    time.sleep(5)  #takes time for this to propigate?


def get_or_create_s3_bucket(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    ## GET OR CREATE S3 Bucket for Lambda funct
    dmcmp = ast.dm_computed
    log_msg("get_or_create_s3_bucket()", info or ast.dm.general.info)
    print(f"\tCreating S3 Bucket {dmcmp.names.s3_bucket_name} for Lambda function")
    create_new_bucket = False
    try:
        results = execute_cmd(ast, refkey='lambda_setup.get_s3_bucket_03', debug=debug, stdout=stdout, info=info)
    except CommandExeception as e:
        if re.search('404', e.stderr):
            print(f"{Fore.YELLOW}Bucket {dmcmp.names.s3_bucket_name} not found")
            create_new_bucket = True
        else:
            raise e
    else:
        print(f"\tS3 bucket {dmcmp.names.s3_bucket_name} already exists!")
    if create_new_bucket:
        results = execute_cmd(ast, section='lambda_setup.create_s3_bucket_04', debug=debug, stdout=stdout, info=info, skip_load_json=True)


def get_or_setup_lambda_fun(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    dmcmp = ast.dm_computed
    log_msg("get_or_setup_lambda_fun()", info or ast.dm.general.info)
    create_new_lambda_func = False
    try:
        results = execute_cmd(ast, refkey='lambda_setup.get_lambda_func_05', debug=debug, stdout=stdout, info=info)
    except CommandExeception as e:
        if re.search('ResourceNotFoundException', e.stderr):
            print(f"Function {dmcmp.names.lambda_fun_name} not found!")
            create_new_lambda_func = True

    ## Create Lambda function
    if(create_new_lambda_func):
        ## NOTE: if you get an error "The role defined for the function cannot be assumed by Lambda."
        ## this might be down to time for the role to propigate to lambda from IAM
        results = execute_cmd(ast, refkey='lambda_setup.create_lambda_func_06', debug=debug, stdout=stdout, info=info)
        if (('computed.lambda_name' in results) and results['computed.lambda_name']):
            print(f"\tLambda function '{results['computed.lambda_name']}' created!")
        else:
            print(f"{Fore.RED}ERROR: Could not create lambda function '{results['computed.lambda_name']}'")
            sys.exit(1)
    else:
        print(f"\tLambda function \"{results['computed.lambda_name']}\" already exists (UPDATING)")
        results = execute_cmd(ast, refkey='lambda_setup.update_lambda_func_06b', debug=debug, stdout=stdout)
        if (('computed.lambda_name' not in results) or not results['computed.lambda_name']):
            print(f"{Fore.RED}ERROR: Could not update lambda function {dmcmp.names.lambda_fun_name}!")
            sys.exit(1)
        time.sleep(1)
        results = execute_cmd(ast, refkey='lambda_setup.update_lambda_func_cfg_06c', debug=debug, stdout=stdout)
        if (('computed.lambda_name' not in results) or not results['computed.lambda_name']):
            print(f"{Fore.RED}: Could not update lambda function config {dmcmp.names.lambda_fun_name}!")
            sys.exit(1)


def get_or_create_authorizer_fun(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    """
    Add the Authorizer Lambda function!
    """
    dmcmp = ast.dm_computed
    log_msg("get_or_create_authorizer_fun()", info or ast.dm.general.info)
    create_new_auth_func = False
    try:
        results = execute_cmd(ast, refkey='lambda_setup.get_lambda_auth_fun', debug=debug, stdout=stdout, info=info)
    except CommandExeception as e:
        if re.search('ResourceNotFoundException', e.stderr):
            print(f"Function {dmcmp.names.lambda_auth_fun_name} not found!")
            create_new_auth_func = True
    ## Create Lambda function
    if(create_new_auth_func):
        results = execute_cmd(ast, refkey='lambda_setup.create_lambda_authorizer', debug=debug, stdout=stdout, info=info)
        if (('computed.returned' in results) and results['computed.returned']):
            print(f"\tLambda function '{results['computed.returned']}' created!")
        else:
            print(f"{Fore.RED}ERROR: Could not create lambda authorizer function '{dmcmp.names.lambda_auth_fun_name}'")
            sys.exit(1)
    else:
        print(f"\tLambda authorizer function \"{dmcmp.names.lambda_auth_fun_name}\" already exists (UPDATING)")
        results = execute_cmd(ast, refkey='lambda_setup.update_lambda_auth_func', debug=debug, stdout=stdout)
        if (('computed.returned' not in results) or not results['computed.returned']):
            print(f"{Fore.RED}ERROR: Could not update lambda function {dmcmp.names.lambda_auth_fun_name}!")
            sys.exit(1)
        time.sleep(1)
        results = execute_cmd(ast, refkey='lambda_setup.update_lambda_auth_func_cfg', debug=debug, stdout=stdout)
        if (('computed.returned' not in results) or not results['computed.returned']):
            print(f"{Fore.RED}: Could not update lambda auth function config {dmcmp.names.lambda_auth_fun_name}!")
            sys.exit(1)


def setup_iam_bucket_policy(
        ast: ActiveState,
        debug: bool = False,
        stdout: bool = False,
        info: bool = False
    ):
    """
    Setup the S3 Bucket policy for lambda role
    """
    dmcmp = ast.dm_computed
    log_msg("setup_iam_bucket_policy()", info or ast.dm.general.info)
    ## Setup IAM policy
    ast.set_refkey(
        'computed.iam_bucket_policy_doc_string',
        json.dumps(dmcmp.json_documents.cy_awsmgr_bucket_policy_doc.toDict())
    )
    # @TODO: Fix this weird bug with aws cli not working without shell here?!?
    results = execute_cmd(ast, refkey='lambda_setup.query_lambda_iam_policy_06d', debug=debug, stdout=stdout, info=info, shell=True)
    if (('computed.policy_s3_name' not in results) or not results['computed.policy_s3_name']):
        print(f"\tCreating policy '{dmcmp.names.lambda_bucket_pol_name}' for lambda")
        results = execute_cmd(ast, refkey='lambda_setup.create_lambda_iam_policy_06e', debug=debug, stdout=stdout, info=info)
        if (('computed.policy_s3_name' not in results) or not results['computed.policy_s3_name']):
            print(f"{Fore.RED}ERROR: Issue creating iam policy '{dmcmp.names.lambda_bucket_pol_name}' for '{dmcmp.names.lambda_fun_name}' lambda function!")
            sys.exit(1)
    else:
        print(f"\tLambda function S3 Bucket IAM Policy '{dmcmp.names.lambda_bucket_pol_name}' already exists!")


def setup_iam_logging_policy(
        ast: ActiveState,
        debug: bool = False,
        stdout: bool = False,
        info: bool = False
    ):
    """
    Setup the logging policy for Lambda role
    """
    dmcmp = ast.dm_computed
    log_msg("setup_iam_logging_policy()", info or ast.dm.general.info)
    ast.set_refkey('computed.iam_logging_policy_doc_string', json.dumps(ast.dm_computed.json_documents.cy_awsmgr_loggroup_policy_doc.toDict()))
    # @TODO: Fix this weird bug with aws cli not working without shell here?!?
    results = execute_cmd(ast, refkey='lambda_setup.query_lambda_iam_policy_06f', debug=False, stdout=False, shell=True)
    if (('computed.policy_log_name' not in results) or not results['computed.policy_log_name']):
        print(f"\tCreating policy '{ast.dm_computed.names.lambda_log_pol_name}' for lambda")
        results = execute_cmd(ast, refkey='lambda_setup.create_lambda_iam_policy_06g', debug=False, stdout=False)
        if (('computed.policy_log_name' not in results) or not results['computed.policy_log_name']):
            print(f"{Fore.RED}ERROR: Issue creating iam policy '{ast.dm_computed.names.lambda_log_pol_name}' for '{ast.dm_computed.names.lambda_fun_name}' lambda function!")
            sys.exit(1)
    else:
            print(f"\tLambda function Log Bucket IAM Policy '{ast.dm_computed.names.lambda_log_pol_name}' already exists!")


def attach_policies_to_lambda_role(
        ast: ActiveState,
        debug: bool = False,
        stdout: bool = False,
        info: bool = False
    ):
    dmcmp = ast.dm_computed
    log_msg("attach_policies_to_lambda_role()", info or ast.dm.general.info)
    results = execute_cmd(ast, refkey='lambda_setup.list_lambda_attached_policies', debug=debug, stdout=stdout, info=info)
    larn = dmcmp.names.lambda_assume_role_name
    lbpm = dmcmp.names.lambda_bucket_pol_name
    llpn = dmcmp.names.lambda_log_pol_name
    if results and 'computed.attached_polices' in results:
        attached_pols = results['computed.attached_polices']
        lbpm_attached = jmespath.search(f"[?PolicyName=='{lbpm}'].PolicyName|[0]", attached_pols)
        llpn_attached = jmespath.search(f"[?PolicyName=='{llpn}'].PolicyName|[0]", attached_pols)
    else:
        lbpm_attached = False
        llpn_attached = False

    if not lbpm_attached:
        print(f"\tAttaching IAM policy '{lbpm}' to role '{larn}'")
        results = execute_cmd(ast, refkey='lambda_setup.attach_iam_lambda_role_policy_7a', debug=debug, stdout=stdout, info=info)
    else:
        print(f"""\tIAM Policy '{lbpm}' is already attached to lambda role '{larn}'!""")

    if not llpn_attached:
        print(f"\tAttaching IAM policy '{llpn}' to role '{larn}'")
        results = execute_cmd(ast, refkey='lambda_setup.attach_iam_lambda_role_policy_7b', debug=debug, stdout=stdout, info=info)
    else:
        print(f"""\tIAM Policy '{llpn}' is already attached to lambda role '{larn}'!""")


def set_lambda_arn(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    ## Get Lambda ARN - SETS computed.lambda_arn
    dmcmp = ast.dm_computed
    log_msg("set_lambda_arn()", info or ast.dm.general.info)
    # @TODO: Fix this weird bug with aws cli not working without shell here?!?
    results = execute_cmd(ast, refkey='lambda_setup.get_lambda_arn_01', debug=debug, stdout=stdout, info=info, shell=True)
    if results and 'computed.returned' in results:
        arns = results['computed.returned']
        if len(arns) == 1:
            lambda_arn = arns[0]
            print(f"\tLambda ({dmcmp.names.lambda_fun_name}) arn : {lambda_arn}")
            ast.set_refkey('computed.lambda_arn', lambda_arn)
        else:
            print(f"{Fore.RED}ERROR: Could not find arn for Lambda {dmcmp.names.lambda_fun_name}")
            sys.exit(1)


def setup_gateway(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    dmcmp = ast.dm_computed
    log_msg(f"setup_gateway(gateway_name = {dmcmp.names.api_gateway_name})", info or ast.dm.general.info)
    # @TODO: Fix this weird bug with aws cli not working without shell here?!?
    results = execute_cmd(ast, refkey='gateway_setup.check_gateway_00', debug=False, stdout=stdout, info=info, shell=True)
    if 'computed.rest_api_gateways' in results:
        rest_api_gateways = results['computed.rest_api_gateways']
    else:
        rest_api_gateways = []

    if( len(rest_api_gateways) > 1):
        print(f"{Fore.RED}ERROR: you have too many ({len(rest_api_gateways)}) duplicated gateways matching {ast.dm_computed.names.api_gateway_name}!")
        sys.exit(1)
    elif (len(rest_api_gateways) == 1):
        print(f"\tGateway {dmcmp.names.api_gateway_name} exists!")
        print(f"\t\t id: {rest_api_gateways[0]['id']}")
        ast.set_refkey('computed.rest_api_id', rest_api_gateways[0]['id'])
        ast.set_refkey('computed.root_resource_id', rest_api_gateways[0]['rootResourceId'])
    else:
        print("\tCreate gateway...")
        results = execute_cmd(ast, refkey='gateway_setup.create_gateway_01', debug=debug, stdout=stdout)
        if 'computed.rest_api_gateway' in results:
            rest_api_gateway = results['computed.rest_api_gateway']
        else:
            rest_api_gateway = {}

        if(not rest_api_gateway):
            print(f"{Fore.RED}ERROR: Issue with creating gateway, nothing returned!")
            sys.exit(1)
        print(f"\tGateway {dmcmp.names.api_gateway_name} created!")
        print(f"\t\t id: {rest_api_gateway['id']}")
        ast.set_refkey('computed.rest_api_id', rest_api_gateway['id'])
        ast.set_refkey('computed.root_resource_id', rest_api_gateway['rootResourceId'])


def get_gateway_root_id(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    dmcmp = ast.dm_computed
    log_msg(f"get_gateway_root_id(gateway_name = {dmcmp.names.api_gateway_name})", info or ast.dm.general.info)
    ## Step 2 : Get Root Resource ID
    results = execute_cmd(ast, refkey='gateway_setup.get_resource_id_02', debug=debug, stdout=stdout, info=info)
    if 'computed.returned' in results and results['computed.returned']:
        gw_resources = results['computed.returned']
        api_gw_root_ids = jmespath.search("items[?path == '/'].id", gw_resources)
        if len(api_gw_root_ids) != 1:
            print(f"{Style.DIM}{pp.pformat(gw_resources)}")
            print(f"{Fore.RED}ERROR: did not find apigateway root id!")
        else:
            api_gw_root_id = api_gw_root_ids[0]
            ast.set_refkey('computed.gw_root_id', api_gw_root_id)
            print(f"\tAPI Gateway root(/) id : {api_gw_root_id}")

        api_gw_deadman_child = jmespath.search(f"items[?path == '/{dmcmp.names.deadman_uri_path}']", gw_resources)
        if len(api_gw_deadman_child) == 1:
            api_gw_deadman_child_id = jmespath.search("id", api_gw_deadman_child[0])
            if api_gw_deadman_child_id:
                print(f"\tAPI Gateway child(/{dmcmp.names.deadman_uri_path}) id : {api_gw_deadman_child_id} -> computed.deadman_child_id")
                ast.set_refkey('computed.deadman_child_id', api_gw_deadman_child_id)
            api_gw_deadman_methods = jmespath.search("resourceMethods", api_gw_deadman_child[0])
            if api_gw_deadman_methods:
                print(f"\tAPI Gateway child(/{dmcmp.names.deadman_uri_path}) methods : {api_gw_deadman_methods} -> computed.deadman_methods")
                ast.set_refkey('computed.deadman_methods', api_gw_deadman_methods)


def create_uri_resources(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    ## Step 3 : Create gateway path resource, SETS computed.resouce_id
    dmcmp = ast.dm_computed
    log_msg(f"create_uri_resource(gateway_name = {dmcmp.names.api_gateway_name}, path = {dmcmp.names.deadman_uri_path})", info or ast.dm.general.info)

    if(('computed' not in dmcmp) and (not dmcmp.computed)):
        print(f"{Fore.RED}ERROR: no computed values found! Missing state information for this call.")
        sys.exit(1)

    if (
        ('deadman_child_id' not in dmcmp.computed) or
        (not dmcmp.computed.deadman_child_id)
    ):
        results = execute_cmd(ast, refkey='gateway_setup.create_resource_03', debug=debug, stdout=stdout, info=info)
        if 'computed.returned' in results and results['computed.returned']:
            child_resource = results['computed.returned']
            api_gw_deadman_child_id = jmespath.search("id", child_resource)
            if api_gw_deadman_child_id:
                print(f"\tAPI Gateway child(/{dmcmp.names.deadman_uri_path}) id : {api_gw_deadman_child_id} -> computed.deadman_child_id")
                ast.set_refkey('computed.deadman_child_id', api_gw_deadman_child_id)
            else:
                print(f"{Fore.RED}ERROR: Failed to create child resource (/{dmcmp.names.deadman_uri_path})")
                sys.exit(1)
            api_gw_deadman_methods = jmespath.search("resourceMethods", child_resource)
            if api_gw_deadman_methods:
                print(f"\tAPI Gateway child(/{dmcmp.names.deadman_uri_path}) methods : {api_gw_deadman_methods} -> computed.deadman_methods")
                ast.set_refkey('computed.deadman_methods', api_gw_deadman_methods, set_value_if_none=False)
    else:
        print(f"{Style.DIM}\t Resource /{dmcmp.names.deadman_uri_path} already exists on apigateway : {dmcmp.names.api_gateway_name}!")


def add_method_to_resource(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    ## Step 4 : Create Method (using resource)
    dmcmp = ast.dm_computed
    log_msg(
        (
            f"add_method_to_resource(gateway_name = "
            f"{ast.dm_computed.names.api_gateway_name}, path = "
            f"{ast.dm_computed.names.deadman_uri_path})"
        ),
        info or ast.dm.general.info
    )

    # results = execute_cmd(ast, refkey='gateway_setup.create_method_04', debug=debug, stdout=stdout, info=info)
    results = execute_cmd(ast, refkey='gateway_setup.get_resource_methods', debug=debug, stdout=stdout, info=info)
    if 'computed.returned' in results and results['computed.returned']:
        child_resources = results['computed.returned']
        api_gw_deadman_child_resources = jmespath.search("resourceMethods", child_resources)
        if (api_gw_deadman_child_resources is None) or ('POST' not in api_gw_deadman_child_resources):
            results = execute_cmd(ast, refkey='gateway_setup.create_method_04', debug=debug, stdout=stdout, info=info)
            if(
                ('computed.returned' in results) and
                results['computed.returned'] and
                jmespath.search("httpMethod", results['computed.returned'])
            ):
                print(f"\tMethod POST created on /{dmcmp.names.deadman_uri_path} child id: {dmcmp.computed.deadman_child_id}")
            else:
                print(f"{Fore.RED}ERROR: Failed to create POST method.")
                sys.exit(1)
        else:
            print(f"\tAlready have resource /{dmcmp.names.deadman_uri_path} child id: {dmcmp.computed.deadman_child_id}) with attached POST method!")
    else:
        print(f"{Fore.RED}ERROR: no computed values found! Missing state information for this call.")
        sys.exit(1)


def add_api_lambda_integration(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    ## Step 5 : Integrate method with the lambda (no results needed)
    dmcmp = ast.dm_computed
    log_msg(f"add_api_lambda_integration(gateway_name = {ast.dm_computed.names.api_gateway_name}, path = {ast.dm_computed.names.deadman_uri_path}, lambda_arn = {ast.dm_computed.computed.lambda_arn})", info or ast.dm.general.info)
    execute_cmd(ast, refkey='gateway_setup.associate_lambda_05', debug=debug, stdout=stdout, info=info)


def get_lambda_perm_policies(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    ## Step 6a : get existing permissions for lambda

    # @TODO: Must fix this to work with state (dev) permission, don't think the other lambda is required
    dmcmp = ast.dm_computed
    log_msg(f"get_lambda_perm_policies(lambda = {dmcmp.names.lambda_fun_name})", info or ast.dm.general.info)
    create_policy = False
    try:
        results = execute_cmd(ast, refkey='gateway_setup.check_lambda_policy', debug=debug, stdout=stdout, info=info)
    except CommandExeception as e:
        if re.search('ResourceNotFoundException', e.stderr):
            print(f"\t{Fore.YELLOW}Policy for {dmcmp.names.lambda_fun_name} not found!")
            return []
        else:
            raise e
    else:
        if 'computed.returned' in results and results['computed.returned']:
            lambda_policies = results['computed.returned']
            pol = jmespath.search('Policy', lambda_policies)
            return pol
        return []


def set_lambda_perm_policy(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    ## Step 6 : Grant api gateway permission to invoke lambda function (no results needed)
    ## Maybe setup_lambda_invoke_perm_06 is wrong or not needed, swapped for setup_apigate_execute_perm
    ## to update you need to remove it: aws lambda remove-permission --function-name myLambdaFunction --statement-id apigateway-test-1
    # list permissions:  aws lambda get-policy --function-name SaveDateTimeToS3 | jq '.Policy |= fromjson'
    dmcmp = ast.dm_computed
    log_msg(f"set_lambda_perm_policy(lambda = {dmcmp.names.lambda_fun_name})", info or ast.dm.general.info)
    pol = get_lambda_perm_policies(ast, debug=debug, stdout=stdout, info=info)
    if isinstance(pol, str):
        pol = json.loads(pol)
    sid_invoke_perm = jmespath.search("Statement[?Principal.Service == 'apigateway.amazonaws.com']", pol)

    if((not sid_invoke_perm) or (len(sid_invoke_perm) == 0)):
        execute_cmd(ast, refkey='gateway_setup.setup_apigate_execute_perm', debug=debug, stdout=stdout, info=info)
    else:
        print(f"{Style.DIM}\tLambda awsgateway permission already exists")


# def get_attached_authorizers(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False) -> dict:
#     # Returns all attached authorizers for the apigateway
#     # aws apigateway get-authorizers --rest-api-id <apigateway id>
#     dmcmp = ast.dm_computed
#     log_msg(f"get_attached_authorizers(apigateway_id = {dmcmp.computed.rest_api_id})", info or ast.dm.general.info)
#     results = execute_cmd(ast, refkey='gateway_setup.get_authorizers', debug=debug, stdout=debug)
#     if 'computed.returned' in results and results['computed.returned']:
#         authorizers = results['computed.returned']
#         authorizer = jmespath.search(f"items[?name == '{dmcmp.names.apigateway_authorizer_name}']|[0]", authorizers)
#         if authorizer:
#             authorizer_id = jmespath.search(f"id", authorizer)
#             if authorizer_id:
#                 print(f"\tAPI Gateway authorizer(/{dmcmp.names.apigateway_authorizer_name}) id : {authorizer_id} -> computed.apigateway_authorizer_id")
#                 ast.set_refkey('computed.apigateway_authorizer_id', authorizer_id)
#         return authorizer
#     else:
#         return {}


# def setup_apigateway_authorizer(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
#     # Working cli to setup a TOKEN authorizor:
#     # aws apigateway create-authorizer \
#     #   --rest-api-id <rest api id> \
#     #   --name <authorizor unique name> \
#     #   --type TOKEN \
#     #   --authorizer-uri 'arn:aws:apigateway:<region>:lambda:path/2015-03-31/functions/arn:aws:lambda:<region>:<account id>:function:<name of lambda func>/invocations' \
#     #   --identity-source 'method.request.header.<header label>' --authorizer-result-ttl-in-seconds 300
#     # header label Authorization
#     dmcmp = ast.dm_computed
#     log_msg(f"setup_apigateway_authorizer(lambda = {dmcmp.names.lambda_fun_name})", info or ast.dm.general.info)

#     authorizer = get_attached_authorizers(ast, debug=debug, stdout=stdout, info=info)
#     if not authorizer:
#         results = execute_cmd(ast, refkey='gateway_setup.setup_authorizer', debug=debug, stdout=debug)
#         if 'computed.returned' in results and results['computed.returned']:
#             authorizers = results['computed.returned']
#             authorizer = jmespath.search(f"items[?name == '{dmcmp.names.apigateway_authorizer_name}']|[0]", authorizers)
#             if authorizer:
#                 authorizer_id = jmespath.search(f"id", authorizer)
#                 if authorizer_id:
#                     print(f"\tAPI Gateway authorizer(/{dmcmp.names.apigateway_authorizer_name}) id : {authorizer_id} -> computed.apigateway_authorizer_id")
#                     ast.set_refkey('computed.apigateway_authorizer_id', authorizer_id)
#             return authorizer
#         else:
#             print(f"{Fore.YELLOW}WARNING: no result, may have failed to create authorizer for apigateway!")
#     else:
#         print(f"{Style.DIM}\tAuthorizer {dmcmp.names.apigateway_authorizer_name} for awsgateway already exists")


# def attach_authorizer_to_lambda_method(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
#     # aws apigateway update-method --rest-api-id <api_id> --resource-id <resource_id> --http-method <method> --patch-operations op='replace',path='/authorizationType',value='CUSTOM' op='replace',path='/authorizerId',value='<authorizer_id>'
#     dmcmp = ast.dm_computed
#     log_msg(f"attach_authorizer_to_lambda_method(lambda = {dmcmp.names.lambda_fun_name})", info or ast.dm.general.info)
#     results = execute_cmd(ast, refkey='gateway_setup.attach_lambda_method_api_authorizer', debug=debug, stdout=stdout, info=info)
#     if 'computed.returned' in results and results['computed.returned']:
#         returned = results['computed.returned']
#         if returned:
#             print(f"{Style.DIM}\t/{dmcmp.names.deadman_uri_path} method id {dmcmp.computed.deadman_child_id} attached/updated to use Authorizer {dmcmp.names.apigateway_authorizer_name} id on awsgateway {dmcmp.names.api_gateway_name} id {dmcmp.computed.rest_api_id}")
#         else:
#             print(f"{Fore.YELLOW}WARNING: no result, may have failed to attach/update authorizer for method on apigateway!")


# def add_invoke_authorizer_permission_to_apigateway(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
#     # This runs a command that allows apigatway permissions to invoke our authorizer lambda functions
#     # should probably check if this exists already, then create.
#     dmcmp = ast.dm_computed
#     log_msg(f"add_invoke_authorizer_permission_to_apigateway(lambda = {dmcmp.names.lambda_auth_fun_name} apigateway = {dmcmp.names.api_gateway_name})", info or ast.dm.general.info)
#     invoke_auth_perm_exist = False
#     results = execute_cmd(ast, refkey='gateway_setup.get_lambda_authorizer_policies', debug=debug, stdout=debug)
#     if 'computed.returned' in results and results['computed.returned']:
#         returned = results['computed.returned']
#         if(returned and ('Policy' in returned) and returned['Policy']):
#             policy = json.loads(returned['Policy']) if (type(returned['Policy']) is str) else returned['Policy']
#             if policy:
#                 sid = jmespath.search(f"Statement[?Sid == '{dmcmp.names.authorizer_deadman_post_resource_sid}']", policy)
#                 if sid:
#                     invoke_auth_perm_exist = True
#     if invoke_auth_perm_exist:
#         print(f"\t{Style.DIM}Lambda authorizer apigateway lambda:InvokeFunction already present. Removing...")
#         results = execute_cmd(ast, refkey='gateway_setup.remove_lambda_authorizer_policies', debug=debug, stdout=debug)
#         if 'computed.returned' in results and results['computed.returned']:
#             returned = results['computed.returned']
#             pp.pprint(returned)
#             sys.exit(0)

#     # Latest, after apigateway setup..
#     results = execute_cmd(ast, refkey='gateway_setup.add_lambda_authorizer_invoke_apigateway_permission', debug=debug, stdout=stdout, info=info)
#     if 'computed.returned' in results and results['computed.returned']:
#         returned = results['computed.returned']
#         if 'Statement'in returned:
#             # just assuming this worked..
#             print(f"\t{Style.DIM}\tAdded lambda:InvokeFunction from apigateway permission to {dmcmp.names.lambda_auth_fun_name}'s Resource-based policy statements.")
#         else:
#             print(f"{Fore.RED}ERROR during add_invoke_authorizer_permission_to_apigateway...")
#             sys.exit(1)
#     else:
#         print(f"{Fore.RED}ERROR: call did not return anything!")
#         sys.exit(1)

def create_dev_deployment(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    dmcmp = ast.dm_computed
    log_msg(f"create_dev_deployment(lambda = {ast.dm_computed.names.api_gateway_name})", info or ast.dm.general.info)

    results = execute_cmd(ast, refkey='gateway_setup.deploy_apigateway_07', debug=debug, stdout=debug)
    if 'computed.returned' in results and results['computed.returned']:
        aws_gw_child = results['computed.returned']
        if aws_gw_child:
            print(f"{Style.DIM}\t{dmcmp.names.api_gateway_name} gatewayapi id: {aws_gw_child} state {dmcmp.names.apigateway_stage} deployed.")
        else:
            print(f"{Fore.YELLOW}WARNING: no result, may have failed to deploy state {ast.dm_computed.computed.names.apigateway_stage}.")


def apigateway__create_api_key():
    """
    apigateway create-api-key
    """
    dmcmp = ast.dm_computed
    log_msg(f"apigateway__create_api_key(name = {dmcmp.names.api_key_name})", info or ast.dm.general.info)


def update_dev_deployment(ast: ActiveState, debug: bool = False, stdout: bool = False, info: bool = False):
    dmcmp = ast.dm_computed
    log_msg(f"{Fore.GREEN}update_dev_deployment(lambda = {dmcmp.names.api_gateway_name})", info or ast.dm.general.info)
    results = execute_cmd(ast, refkey='gateway_setup.update_apigateway', debug=debug, stdout=debug)
    pp.pprint(results)


def setup_lambda_stack(ast: ActiveState):
    # create a local tmp directory
    # TODO: Fixes needed, if gateway id changes, must update lambda policy "apigateway-lambda-invoke"!

    path = pathlib.Path(ast.dm.paths.tmp_dir)
    path.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=ast.dm.paths.tmp_dir) as temp_dir:
        print(f"Temporary directory created at: {temp_dir}")
        package_lambdas(ast, debug=False)
        get_api_account(ast, debug=False)
        get_or_create_iam_lambda_assume_role(ast, debug=False)
        get_or_create_s3_bucket(ast, debug=False)
        get_or_setup_lambda_fun(ast, debug=False)
        # get_or_create_authorizer_fun(ast, debug=False)
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
        # setup_apigateway_authorizer(ast, debug=False)
        # add_invoke_authorizer_permission_to_apigateway(ast, debug=False)
        # # update_dev_deployment(ast, debug=False)  # no update data yet (dummy ftm)


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


def provision_api_key(ast: ActiveState, debug: bool = False, stdout: bool = False):
    dmcmp = ast.dm_computed
    if debug or dmcmp.general.debug:
        print(f"provision_api_key()")

    # get account_id & rest_api_id
    get_api_account(ast, debug=debug, stdout=stdout)
    setup_gateway(ast, debug=debug, stdout=stdout)
    get_gateway_root_id(ast, debug=debug, stdout=stdout)

    print(f"Fetching existing keys from aws...")
    ## 1) get existing apigateway API KEYs for our apigateway
    results = execute_cmd(ast, refkey='gateway_setup.aws_apigateway__get_api_keys', debug=debug, stdout=stdout)
    if 'computed.returned' in results and results['computed.returned']:
        apikeys = jmespath.search(f"items[?name == '{dmcmp.names.api_gateway_api_key_name}']", results['computed.returned'])
        if len(apikeys) == 1:
            print(f"\tAPI KEY '{dmcmp.names.api_gateway_api_key_name}' already exists!")
            returned = apikeys[0]
        elif(len(apikeys) > 1):
            print(f"{Fore.RED}ERROR: Too many idential any API keys returned! Aborting")
            sys.exit(1)
        else:
            # No keys
            print(f"Generating key for {dmcmp.names.api_gateway_api_key_name}")
            results = execute_cmd(ast, refkey='gateway_setup.aws_apigateway__create_api_key', debug=debug, stdout=stdout)
            returned = results['computed.returned'] if 'computed.returned' in results else {}
        ## Store the name/value of our api key
        name = returned['name'] if 'name' in returned else None
        create_date = returned['createdDate'] if 'createdDate' in returned else None
        _id = returned['id'] if 'id' in returned else None
        if _id is not None:
            print(f"{Style.DIM}\tapigateway_apikey_id = '{_id}'")
            ast.set_refkey('computed.apigateway_apikey_id', _id)
        value = returned['value'] if 'value' in returned else None
        if value is None:
            prnt_value = '****************************************'
        else:
            prnt_value = value
        print(f"\tAPI KEY ID = {_id}, API KEY VALUE='{prnt_value}'")
    else:
        print(f"{Fore.RED}ERROR: failed to execute get_api_keys command, could not create an api key!")
        sys.exit(1)

    ## 2) Get or Create usage plan
    results = execute_cmd(ast, refkey='gateway_setup.aws_apigateway__get_usage_plans', debug=debug, stdout=stdout)
    if 'computed.returned' in results and results['computed.returned']:
        usageplans = jmespath.search(f"items[?name == '{dmcmp.names.api_gateway_usage_plan_name}']", results['computed.returned'])
        if len(usageplans) == 1:
            print(f"\t{Style.DIM}{dmcmp.names.api_gateway_usage_plan_name} usage plan exists already")
            returned = usageplans[0]
        elif(len(usageplans) > 1):
            print(f"{Fore.RED}ERROR: Too many idential usage plans keys returned! Aborting")
            sys.exit(1)
        else:
            ## no usage plan
            print(f"\t{Fore.CYAN}Creating usage plan {dmcmp.names.api_gateway_usage_plan_name}")
            print(f"\tUsage plan name = '{dmcmp.names.api_gateway_usage_plan_name}, key id = '{ast.dm_computed.computed.apigateway_apikey_id}'")
            results = execute_cmd(ast, refkey='gateway_setup.aws_apigateway__create_usage_plan', debug=debug, stdout=stdout)
            if 'computed.returned' in results and results['computed.returned']:
                returned = results['computed.returned']
            else:
                print(f"{Fore.RED}Error: results form refkey='gateway_setup.aws_apigateway__create_usage_plan' failed!")
                sys.exit(1)

        name = returned['name'] if 'name' in returned else None
        _id = returned['id'] if 'id' in returned else None
        apiStages = returned['apiStages'] if 'apiStages' in returned else []
        if _id is not None and name == dmcmp.names.api_gateway_usage_plan_name:
            print(f"\t{Style.DIM}api_gateway_usage_plan_name = {dmcmp.names.api_gateway_usage_plan_name}, apigateway_usage_plan_id = {_id}")
            ast.set_refkey('computed.apigateway_usage_plan_id', _id)
        else:
            print(f"{Fore.RED}ERROR: Couldn't find usage plan id for {dmcmp.names.api_gateway_usage_plan_name}!")
            sys.exit(1)

        cur_api_stage_id = jmespath.search(f"[?apiId== '{ast.dm_computed.computed.rest_api_id}' && stage == '{dmcmp.names.apigateway_stage}'].apiId", apiStages)
        if len(cur_api_stage_id) == 1:
            print(f"\t{Style.DIM}Gateway API ID for Stage '{dmcmp.names.apigateway_stage}' = {ast.dm_computed.computed.rest_api_id} already associated with usage plan")
        elif len(cur_api_stage_id) > 1:
            print(f"{Fore.RED}ERROR: Too many idential usage plans keys returned! Aborting")
            sys.exit(1)
        else:
            print(f"\tAdding API Gateway Stage '{dmcmp.names.apigateway_stage}' rest_api_id = {ast.dm_computed.computed.rest_api_id} to usage plan {ast.dm_computed.computed.apigateway_usage_plan_id}!")
            ## Connect apigateway to this usage plan
            results = execute_cmd(ast, refkey='gateway_setup.aws_apigateway__update_usage_plan', debug=debug, stdout=stdout)

    ## 3) Assign our API key
    results = execute_cmd(ast, refkey='gateway_setup.aws_apigateway__get_usage_plan_keys', debug=debug, stdout=stdout)
    if 'computed.returned' in results and results['computed.returned']:
        usage_plan_associated_api_key = jmespath.search(f"items[?id == '{ast.dm_computed.computed.apigateway_apikey_id}']", results['computed.returned'])
    else:
        usage_plan_associated_api_key = []

    if len(usage_plan_associated_api_key) == 1:
        print(f"\t{Style.DIM}apigateway_apikey_id = '{ast.dm_computed.computed.apigateway_apikey_id}' already associated with apigateway_usage_plan_id = {ast.dm_computed.computed.apigateway_usage_plan_id}")
    else:
        results = execute_cmd(ast, refkey='gateway_setup.aws_apigateway__create_usage_plan_key', debug=debug, stdout=stdout)
        if 'computed.returned' in results and results['computed.returned']:
            returned = results['computed.returned']
            print(f"\t{Style.DIM}apigateway_apikey_id = '{ast.dm_computed.computed.apigateway_apikey_id}' is now associated with apigateway_usage_plan_id = {ast.dm_computed.computed.apigateway_usage_plan_id}")


def main(ast: ActiveState, args: bool, parser: argparse.ArgumentParser):
    """
    Create lambda function and api gateway
    """
    if args.setup_stack:
        setup_lambda_stack(ast)
    elif args.test_deadman:
        print("Testing...")
        test_deadman_url(ast)
    elif args.provision_api_key:
        print("Provisioning API key on lambda stack")
        provision_api_key(ast)
    else:
        parser.print_help()
        print("\nMust include one of the following flags:")
        print("--setup-stack | --test-deadman | --provision-api-key")
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
    parser.add_argument('--setup-stack', action='store_true')
    parser.add_argument('--test-deadman', action='store_true')
    parser.add_argument('--provision-api-key', action='store_true')
    args = parser.parse_args()
    if((args.config_path is not None)):
        ast = ActiveState(args.config_path)
    else:
        ast = ActiveState(bin_path / 'cyawsmgr_config.ini')
    if((args.profile is None) and 'awsprofile' in ast.dm.general) and ast.dm.general['awsprofile']:
        profile = ast.dm.general['awsprofile']
    elif('AWS_PROFILE' in os.environ):
        profile = os.environ.get('AWS_PROFILE', None)
        ast.dm.general.awsprofile = profile
    else:
        profile = args.profile
        ast.dm.general.awsprofile = profile

    if(profile is None):
        parser.print_help()
        print("\nError: No default profile, use --profile <name>")
        sys.exit(1)

    if((args.region is None) and 'awsregion' in ast.dm.general) and ast.dm.general['awsregion']:
        region = ast.dm.general['awsregion']
    elif('AWS_REGION' in os.environ):
        region = os.environ.get('AWS_REGION', None)
        ast.dm.general.awsregion = region
    else:
        region = args.region
        ast.dm.general.awsregion = region

    if(region is None):
        ## TODO Use environment?
        parser.print_help()
        print("\nError: No default region, use --region <name>")
        sys.exit(1)

    main(ast, args, parser)
