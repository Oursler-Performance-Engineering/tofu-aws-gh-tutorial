# You cannot create a new backend by simply defining this and then
# immediately proceeding to "terraform apply". The S3 backend must
# be bootstrapped according to the simple yet essential procedure in
# https://github.com/cloudposse/terraform-aws-tfstate-backend#usage
module "terraform_state_backend" {
  source      = "cloudposse/tfstate-backend/aws"
  version     = "v1.5.0"

  namespace  = "example"
  stage      = "dev"
  name       = "github-role-stack"
  attributes = ["state"]

  terraform_backend_config_file_path = "."
  terraform_backend_config_file_name = "backend.tf"
  force_destroy                      = false
}

module "iam_github_oidc_provider" {
  count = 0

  source    = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-provider"
  version   = "v5.54.0"
}

module "iam_github_write_role" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-role"
  version   = "v5.54.0"

  name = "github-write-role"

  subjects = ["justin-o12/tofu-gh-example:ref:refs/heads/main"]

  policies = {
    AmazonVPCFullAccess = "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
    AmazonS3FullAccess = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
    AmazonDynamoDBFullAccess = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  }
}

module "iam_github_read_role" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-role"
  version   = "v5.54.0"

  name = "github-read-role"

  subjects = ["justin-o12/tofu-gh-example:*"]

  policies = {
    ReadOnlyAccess = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  }
}
