#!/usr/bin/env bash
set -x

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT $0: $1"
}

# authenticate to Vault
vault login password

logger "Enable AWS secret backend in Vault"
vault secrets enable aws

logger "Configure AWS secret credentials in Vault"
vault kv put aws/config/root \
access_key=${AWS_ACCESS_KEY_ID}  \
secret_key=${AWS_SECRET_ACCESS_KEY}  \
region=${AWS_DEFAULT_REGION}

logger "Configure the lease time for generated credentials"
vault kv put aws/config/lease lease=1m lease_max=5m

logger "Create a role with associated policy for the short lived credentials"
echo '
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::${AWS_S3_BUCKET}"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": ["arn:aws:s3:::${AWS_S3_BUCKET}/*"]
    }
  ]
}' > iam.policy
vault kv put aws/roles/s3access policy=@iam.policy
