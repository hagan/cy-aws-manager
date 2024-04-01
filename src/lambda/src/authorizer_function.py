import os
import logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    logger.info("authorizer_function.handler() called!")
    token_file = 'token.txt'

    with open(token_file, 'r') as file:
        expected_token = file.read().strip()

    # Extract the token from the incoming request
    token = event['authorizationToken']

    # Compare the extracted token to your fixed token
    logger.info(f'expected: {expected_token}')
    logger.info(f'     got: {token}')
    # if f'Bearer {expected_token}' == token:
    if True:
        # Return an IAM policy that allows access
        return generate_policy('deadman', 'Allow', event['methodArn'])
    else:
        # Return an IAM policy that denies access
        return generate_policy('deadman', 'Deny', event['methodArn'])


def generate_policy(principal_id, effect, resource):
    return {
        'principalId': principal_id,
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [{
                'Action': 'execute-api:Invoke',
                'Effect': effect,
                'Resource': resource
            }]
        }
    }