# rosa-create
## Prerequisites
```
https://docs.google.com/document/d/1w-9ifM2ddZEGFfJkuNQB3ofkdRnZEv42BDMGhCYuokk/edit#heading=h.v1h8kuinf9z7
```

### Create backend
```
# https://github.com/mmwillingham/github_actions-terraform-aws-backend/blob/main/.github/workflows/backend.yaml
# NOTE: NEED TO ENABLE THIS FOR STS
# Until then, update Github Actions > Secrets with AWS AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY

# Clone repo
https://github.com/mmwillingham/github_actions-terraform-aws-backend

Update vars.tf

# Run job
Actions > Terraform-GitHub-Actions-BACKEND > Run workflow
```

### Create OIDC
```
export REGION="us-east-2"
export AWS_ACCOUNT_ID=997649724060
# NOTE: for the following command, the thumbprint is the same for every GitHub repo.
export GITHUB_OIDC_ARN=$(aws --region "$REGION" iam create-open-id-connect-provider --url "https://token.actions.githubusercontent.com" --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" --client-id-list 'sts.amazonaws.com' --output text)
export GITHUB_ORG="mmwillingham"
export GITHUB_REPO1="rosa-create"
export GITHUB_REPO2="rosa-create-existing-vpc"
export GITHUB_REPO3="rosa-create-vpc"
export GITHUB_BRANCH="main"


# Quick verify
aws iam list-open-id-connect-providers --output text

echo $REGION, $AWS_ACCOUNT_ID, $GITHUB_OIDC_ARN, $GITHUB_ORG, $GITHUB_REPO1, $GITHUB_REPO2, $GITHUB_REPO3, $GITHUB_BRANCH
```
### Create secret with ocm_token and admin_password
```
# Create a secret (bucket) in Secrets Manager
# NOTE: This will create a single secret (bucket) in AWS containing multiple key/value pairs

OCM_TOKEN="<redacted>"

ADMIN_PASSWORD="RedHatOpenShift123"

cat << EOF > rosa_token.json
{
    "ocm_token": "$OCM_TOKEN",
    "ADMIN_PASSWORD": "$ADMIN_PASSWORD"
}
EOF
cat rosa_token.json

OCM_TOKEN_SECRET_NAME=rosa_secret_v1
OCM_TOKEN_SECRET_ARN=$(aws --region "$REGION" secretsmanager create-secret --name ${OCM_TOKEN_SECRET_NAME} --secret-string file://rosa_token.json --query ARN --output text)
echo $OCM_TOKEN_SECRET_ARN
```
### Create AWS secrets policy
```
# You may want to allow access to a wildcard instead of a specific secret arn by uncommenting the line for Resource and commenting the previous line.

cat << EOF > secret_policy.json
{
   "Version": "2012-10-17",
   "Statement": [{
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": ["$OCM_TOKEN_SECRET_ARN"]
      #"Resource": "*"
      }]
}
EOF

# Verify the variables were correctly populated
cat secret_policy.json

# Create an IAM Access Policy

SECRET_POLICY_ARN=$(aws --region "$REGION" --query Policy.Arn --output text iam create-policy --policy-name github-access-to-${OCM_TOKEN_SECRET_NAME}-policy --policy-document file://secret_policy.json)
echo $SECRET_POLICY_ARN
```
### Create S3 buckets policy
```
# You may want to limit access to a specific bucket instead of *.

cat << EOF > s3_policy.json
{
"Version": "2012-10-17",
"Statement": [
 {
   "Effect": "Allow",
   "Action": [
     "s3:CreateBucket",
     "s3:DeleteBucket",
     "s3:PutBucketTagging",
     "s3:GetBucketTagging",
     "s3:PutEncryptionConfiguration",
     "s3:GetEncryptionConfiguration",
     "s3:PutLifecycleConfiguration",
     "s3:GetLifecycleConfiguration",
     "s3:GetBucketLocation",
     "s3:ListBucket",
     "s3:GetObject",
     "s3:PutObject",
     "s3:DeleteObject",
     "s3:ListBucketMultipartUploads",
     "s3:AbortMultipartUpload",
     "s3:ListMultipartUploadParts",
     "ec2:DescribeSnapshots",
     "ec2:DescribeVolumes",
     "ec2:DescribeVolumeAttribute",
     "ec2:DescribeVolumesModifications",
     "ec2:DescribeVolumeStatus",
     "ec2:CreateTags",
     "ec2:CreateVolume",
     "ec2:CreateSnapshot",
     "ec2:DeleteSnapshot"
   ],
   "Resource": "*"
 }
]}
EOF

S3_POLICY_ARN=$(aws iam create-policy --policy-name "GitHub-S3Access" --policy-document file://s3_policy.json --query Policy.Arn --output text)

echo ${S3_POLICY_ARN}
```
### Create dynamoDB policy
```
# You may want to limit access to a specific table instead of *.

cat << EOF > dynamodb_policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllAPIActionsOnBooks",
            "Effect": "Allow",
            "Action": "dynamodb:*",
            "Resource": "*"
        }
    ]
}
EOF

dynamodb_POLICY_ARN=$(aws iam create-policy --policy-name "GitHub-dynamodbAccess" --policy-document file://dynamodb_policy.json --query Policy.Arn --output text)

echo ${dynamodb_POLICY_ARN}
```
### Create IAM/R53/EC2 policy
```
# You may want to limit access to a specific resources instead of *.

cat << EOF > create_cluster_policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:*",
                "ec2:*",
                "route53:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF

create_cluster_POLICY_ARN=$(aws iam create-policy --policy-name "GitHub-create_clusterAccess" --policy-document file://create_cluster_policy.json --query Policy.Arn --output text)

echo ${create_cluster_POLICY_ARN}
```
### Create role and trust policies
```
cat << EOF > trustpolicyforGitHubOIDC.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "${GITHUB_OIDC_ARN}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/${GITHUB_BRANCH}",
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
EOF

NOTE: Or if you want to allow trust from any repo and branch in the github rorganization:

cat << EOF > trustpolicyforGitHubOIDC.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "${GITHUB_OIDC_ARN}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": [
                      "repo:${GITHUB_ORG}/${GITHUB_REPO1}:*",
                      "repo:${GITHUB_ORG}/${GITHUB_REPO2}:*",
                      "repo:${GITHUB_ORG}/${GITHUB_REPO3}:*",
                      "repo:${GITHUB_ORG}:*" ]
                 },
                 "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                 }
            }
        }
    ]
}
EOF

aws --region "$REGION" iam create-role --role-name GitHubAction-AssumeRoleWithAction --assume-role-policy-document file://trustpolicyforGitHubOIDC.json

export GITHUB_ROLE_ARN=$(aws iam get-role --role-name=GitHubAction-AssumeRoleWithAction --query 'Role.[Arn]' --output text)
echo $GITHUB_ROLE_ARN

# Attach the role to the AWS Secrets Manager policy
aws iam attach-role-policy --role-name GitHubAction-AssumeRoleWithAction --policy-arn $SECRET_POLICY_ARN

# Attach the role to the S3 policy
aws iam attach-role-policy --role-name GitHubAction-AssumeRoleWithAction --policy-arn $S3_POLICY_ARN

# Attach the role to the dynamodb policy
aws iam attach-role-policy --role-name GitHubAction-AssumeRoleWithAction --policy-arn $dynamodb_POLICY_ARN

# Attach the role to the create_cluster policy
aws iam attach-role-policy --role-name GitHubAction-AssumeRoleWithAction --policy-arn $create_cluster_POLICY_ARN


# Verify attachment
aws iam list-attached-role-policies --role-name GitHubAction-AssumeRoleWithAction --output text
ATTACHEDPOLICIES	arn:aws:iam::997649724060:policy/GitHub-dynamodbAccess	GitHub-dynamodbAccess
ATTACHEDPOLICIES	arn:aws:iam::997649724060:policy/github-access-to-rosa_secret_v1-policy	github-access-to-rosa_secret_v1-policy
ATTACHEDPOLICIES	arn:aws:iam::997649724060:policy/GitHub-create_clusterAccess	GitHub-create_clusterAccess
ATTACHEDPOLICIES	arn:aws:iam::997649724060:policy/GitHub-S3Access	GitHub-S3Access
```
## Prepare GitHub files
```
# Clone repo
git clone https://github.com/mmwillingham/rosa-create

# Configure STS in the Github Actions workflow
## If not already present, add these token permissions to workflow under job name
   permissions: # This and the next two lines are required for accessing AWS as an OIDC provider
      id-token: write
      contents: read

Example:
jobs:
  rosa-create-with-vpc:
    name: init-plan-apply
    runs-on: ubuntu-latest
    permissions: # This and the next two lines are required for accessing AWS as an OIDC provider
      id-token: write
      contents: read
    steps:
      - name: Checkout
        uses: actions/checkout@v4

# Update for AWS credentials
# for role, use value from $GITHUB_ROLE_ARN
echo $GITHUB_ROLE_ARN

      - name: configure aws credentials
        uses: aws-actions/configure-aws-credentials@v3
        with:
          role-to-assume: arn:aws:iam::997649724060:role/GitHubAction-AssumeRoleWithAction
          role-session-name: samplerolesession
          aws-region: ${{ env.AWS_REGION }}

# for secret_ids, use $OCM_TOKEN_SECRET_ARN

        with:
          secret-ids: |
            TF_VAR,arn:aws:secretsmanager:us-east-2:997649724060:secret:rosa_secret_v1-qysNU9

# Update backend.tfvars with values from "Create terraform backend for state"
region         = "us-east-2"
bucket         = "rosa-tfstate-20240517-2"
dynamodb_table = "rosa-tfstate-20240517-2"
key            = "terraform.tfstate"

# Update <env>.tfvars (or add new .tfvars file) THIS MAY NEED TO BE UPDATED
cluster_name = "bosez-gdabs3"
openshift_version            = "4.15.10"
    ## For available stable versions: rosa list versions --channel-group stable

upgrade_acknowledgements_for = "4.15"
cloud_region = "us-east-2"
admin_username = "bolauder"
account_role_prefix = "bosez-123456"
operator_role_prefix = "bosez-123456"

## For 3 availability zones
# multi_az                     = true
# availability_zones           = ["us-east-2a", "us-east-2b", "us-east-2c"]
# replicas                     = 3


## For 1 availability zone
multi_az                     = false
availability_zones           = ["us-east-2a"]
replicas                     = 2

# not sure if I need this
bucket         = "rosa-tfstate-20240517-2"
dynamodb_table = "rosa-tfstate-20240517-2"
dynamoDB_table = "rosa-tfstate-20240517-2"
key            = "terraform.tfstate"
```

# Run workflow
Github > Actions > (select workflow for your <environment>) > Run workflow > Select branch > Run workflow
NOTE: I'm currently running this the main branch.
This is set to manual trigger. It can be triggered in many other ways.


