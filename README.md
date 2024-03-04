# Cyverse AWS Manager

version: 0.0.1

#### Prereqs

  * Setup direnv in your bash/zsh environment: https://direnv.net/
  * Setup pyenv or similar to setup poetry for flask -> <project>/src/flask/README.md for more info


#### Git submodules/HOWTO

To clone repo:
```
  git clone --recurse-submodules <repo url>

  # OR
  git clone <repo url> <project dir name>
  cd <project dir name>
  ## For the very first time you clone a project:
  git submodule update --init --recursive
```

To update project

```
  cd <project dir name>
  git pull

  ## Note: after executing the command below, this will place the submodules
  ## directories: ./src/flask, ./src/ui, & ./src/vice in detached states.
  ## This will not update/pull each sumodule's main branch to its current!
  git submodule update --recursive --remote
```

Updating project &/or submodules...
Note: Sometimes a repo submodule will become detached if you checkout the root project space (by design). To make a change and/or commit:
```
  cd <project>/src/ui; git checkout main; .. work ..; git commit -am "update react thing"; git push
  cd <project>/src/flask; git checkout main; .. work ..; git commit -am "updated flask thing"; git push
  cd <project>/src/vice; git checkout main; .. work ..; git commit -am "updated docker vice stuff"; git push
  cd <project>; git commit -am "updated all the things"; git push
```

#### Git LFS

MacOS/OSX
$ brew install git-lfs

Linux/Debian
$ apt install git-lfs

And you do not need to run `git lfs install` as hooks are already in .git/hook or .husky folders.

## Compiling docker images

#### Setup our builder environment

  docker buildx create --name mybuilder --use
  docker buildx inspect --bootstrap
  docker login

#### Create images for hub

~Warning this takes time to compile, 6+ hours. Only needed once, use hub.docker.com instead
Note: Now awsmgr takes about 30mins... After modifying pynode/pulumi to take less time, taking longer to build the image, dunno why

  1. adjust config.mk to reflect docker hub user etc...
  2. `$> make NOCACHE=yes DOCKERHUB=yes build-pynode-image`
  3. `$> make NOCACHE=yes DOCKERHUB=yes build-pulumi-image`
  4. `$> make NOCACHE=yes DOCKERHUB=yes build-awsmgr-image`
  5. `$> make NOCACHE=yes DOCKERHUB=yes build-vice-image`

Note: Only recompile step 5 unless you need to modify the Python/NodeJS/AWS/Pulumi root alpine Image. Only takes ~1 minute

#### Simplify C&C of AWS resources

There are 4 elements of this project (cy-aws-manager)

  1. VICE Docker image for use Cyverse infrasturcture: [https://github.com/hagan/cy-vice-aws-manager](https://github.com/hagan/cy-vice-aws-manager)
  2. Lambda functions for AWS C&C: TBD
  3. NextJS/Express for UX: [https://github.com/hagan/cy-ui-aws-manager](https://github.com/hagan/cy-ui-aws-manager)
  4. Flask UX application for vice app: [https://github.com/hagan/cy-flask-aws-manager](https://github.com/hagan/cy-flask-aws-manager)


### How to create an AWS_SESSION_TOKEN for service

Required: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

Setup credentials for your main admin user with permissions high enough to create a new user/role

`$> aws configure`

Output:

```
AWS Access Key ID [None]: AKI**************
AWS Secret Access Key [None]: ****************************************
Default region name [None]: us-west-2
Default output format [None]: json
```

OR if SSO auth happens to be working for you...

`$> aws configure sso`

```
SSO session name (Recommended): default-sso
SSO start URL [None]: Url to your SSO login page
SSO region [None]: us-west-2
SSO registration scopes [sso:account:access]:
```

1. Create a user specificially for awsmgr on your AWS account (least privilges)

    `$> aws iam create-user --user-name ua-data7-awsmgr`

    Output:

    ```
    {
        "User": {
            "Path": "/",
            "UserName": "ua-data7-awsmgr",
            "UserId": "AID**************",
            "Arn": "arn:aws:iam::1234557890:user/ua-data7-awsmgr",
            "CreateDate": "2024-02-29T20:16:27+00:00"
        }
    }
    ```

2. Create an IAM policy for our project. Example: `~project~/iam-policies/ua-data7-amwsmgr-policy.json` is a starting point (minimize services & resources needed).

    `$> aws iam create-policy --policy-name AWSManagerFullAccessPolicy --policy-document file://iam-policies/ua-data7-awsmgr-policy.json`

    Output:

    ```
    {
        "Policy": {
            "PolicyName": "AWSManagerFullAccessPolicy",
            "PolicyId": "ANP**************",
            "Arn": "arn:aws:iam::1234557890:policy/AWSManagerFullAccessPolicy",
            "Path": "/",
            "DefaultVersionId": "v1",
            "AttachmentCount": 0,
            "PermissionsBoundaryUsageCount": 0,
            "IsAttachable": true,
            "CreateDate": "2024-02-29T20:21:18+00:00",
            "UpdateDate": "2024-02-29T20:21:18+00:00"
        }
    }
    ```

3. Attach policy to user

    `$> aws iam attach-user-policy --user-name ua-data7-awsmgr --policy-arn "arn:aws:iam::##AWS ACCOUNT ID##:policy/AWSManagerFullAccessPolicy"`

4. If you need an access key (not a temporary session key)  you can generate, otherwise skip step.

    `$> aws iam create-access-key --user-name ua-data7-awsmgr`

    Output (Sensitive/don't share):

    ```
    {
        "AccessKey": {
            "UserName": "ua-data7-awsmgr",
            "AccessKeyId": "AKI**************",
            "Status": "Active",
            "SecretAccessKey": "****************************",",
            "CreateDate": "2024-02-29T20:25:27+00:00"
        }
    }
    ```

5. Verify it created the account

    `$> aws iam list-attached-user-policies --user-name ua-data7-awsmgr`

    Output:

    ```
    {
        "AttachedPolicies": [
            {
                "PolicyName": "AWSManagerFullAccessPolicy",
                "PolicyArn": "arn:aws:iam::1234557890:policy/AWSManagerFullAccessPolicy"
            }
        ]
    }
    ```

7. Edit ua-data7-awsmgr-trust-policy.json, replace your AWS Account ID and setup Trust policy for our ua-data7-awsmgr user.

    `$> aws iam create-role --role-name AWSManagerRole --assume-role-policy-document file://iam-policies/ua-data7-awsmgr-trust-policy.json`

    Output:

    ```
    {
        "Role": {
            "Path": "/",
            "RoleName": "AWSManagerRole",
            "RoleId": "ARO**************",
            "Arn": "arn:aws:iam::1234557890:role/AWSManagerRole",
            "CreateDate": "2024-02-29T21:05:17+00:00",
            "AssumeRolePolicyDocument": {
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "AWS": "arn:aws:iam::1234557890:user/ua-data7-awsmgr"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }
        }
    }
    ```

8. Attach Policy to the AWSManagerRole

    Show all local policies to this account (lots)

    `$> aws iam list-policies --scope Local --query "Policies[?starts_with(PolicyName, 'AWSManagerFullAccessPolicy')]"`

    Output:

    ```
    [
        {
            "PolicyName": "AWSManagerFullAccessPolicy",
            "PolicyId": "ANP**************",
            "Arn": "arn:aws:iam::1234557890:policy/AWSManagerFullAccessPolicy",
            "Path": "/",
            "DefaultVersionId": "v1",
            "AttachmentCount": 2,
            "PermissionsBoundaryUsageCount": 0,
            "IsAttachable": true,
            "CreateDate": "2024-02-29T20:21:18+00:00",
            "UpdateDate": "2024-02-29T20:21:18+00:00"
        }
    ]
      ```

    Attach AWSManagerFullAccessPolicy to our AWSManagerRole, role...

    `$> aws iam attach-role-policy --role-name AWSManagerRole --policy-arn "arn:aws:iam::1234557890:policy/AWSManagerFullAccessPolicy"`

9. Add ua-data7-awsmgr to aws cli profiles ()

    `$> aws configure --profile ua-data7-awsmgr`

    Use credentials created in step 4

```
AWS Access Key ID [None]: AKI**************
AWS Secret Access Key [None]: ****************************************
Default region name [None]: us-west-2
Default output format [None]: json
```

9. Verify policy is attached to role

    `$> aws iam list-attached-role-policies --role-name AWSManagerRole`

    Output:

    ```
    {
        "AttachedPolicies": [
            {
                "PolicyName": "AWSManagerFullAccessPolicy",
                "PolicyArn": "arn:aws:iam::1234557890:policy/AWSManagerFullAccessPolicy"
            }
        ]
    }
    ```

10. Generate temporary session token (token will expire in 1 hours / 3600 seconds)

    `$> aws --profile ua-data7-awsmgr sts assume-role --role-arn "arn:aws:iam::1234557890:role/AWSManagerRole" --role-session-name "AwsManagerRoleSession" --duration-seconds 3600`

    Other options (2FA/MFA)
    --serial-number arn:aws:iam::1234557890:mfa/MFA_DEVICE_NAME
    --token-code MFA_CODE`

    Output (This will be used for the Cyverse DE analysis paramaters section, also consider this sensitive & don't share):

    ```
    {
        "Credentials": {
            "AccessKeyId": "ASI**************",",
            "SecretAccessKey": "****************************************",
            "SessionToken": "**..**",
            "Expiration": "2024-02-29T22:31:17+00:00"
        },
        "AssumedRoleUser": {
            "AssumedRoleId": "ARO**************:AWSManagerRoleSession",
            "Arn": "arn:aws:sts::1234557890:assumed-role/AWSManagerRole/AWSManagerRoleSession"
        }
    }
    ```

11. Test least privileged account with Temporary Session key

    `$> aws configure --profile awsmgr-token`

    ```
    AWS Access Key ID [None]: ASI**************
    AWS Secret Access Key [None]: ****************************************
    Default region name [None]: us-west-2
    Default output format [None]: json
    ```

    Set the session token (expires in ~1 hour)

    `$> aws configure --profile awsmgr-token set aws_session_token  **. SessionToken goes here .**`

    Test that our Role is working

    `$> aws --profile awsmgr-token sts get-caller-identity`

    ```
    {
        "UserId": "ARO*****************:AwsManagerRoleSession",
        "Account": "1234557890",
        "Arn": "arn:aws:sts::1234557890:assumed-role/AWSManagerRole/AwsManagerRoleSession"
    }
    ```

    List off ec2 instances

    `$> aws --profile awsmgr-token ec2 describe-instances --region us-west-2`

    Output:

    ```
      {
        "Reservations": [
            {
                "Groups": [],
                "Instances": [
                    {
                        "AmiLaunchIndex": 0,
                        "ImageId": "ami-091f300417a06d788",
                        "InstanceId": "i-****************",
                        "InstanceType": "t2.large",
                        "KeyName": "id_rsa_windows_server",
                        "LaunchTime": "2024-01-19T22:21:02+00:00",
                        "Monitoring": {
                            "State": "disabled"
                        },
    ```



## Issues

  - using docker buildx sometimes uninstalls itself?
    $ apt install docker-buildx-plugin
    $ docker buildx install