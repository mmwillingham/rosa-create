cluster_name = "bosez-123456"
openshift_version            = "4.15.10"
    ## For available stable versions: rosa list versions --channel-group stable

upgrade_acknowledgements_for = "4.15"
cloud_region = "us-east-2"
admin_username = "bolauder"
account_role_prefix = "bosez-ar-20240618"
operator_role_prefix = "bosez-or-20240618"

## For 3 availability zones
# multi_az                     = true
# availability_zones           = ["us-east-2a", "us-east-2b", "us-east-2c"]
# replicas                     = 3


## For 1 availability zone
multi_az                     = false
availability_zones           = ["us-east-2a"]
replicas                     = 2

# not sure if I need this
bucket         = "rosa-tfstate-20240618"
dynamodb_table = "rosa-tfstate-20240618"
dynamoDB_table = "rosa-tfstate-20240618"
key            = "terraform.tfstate"
