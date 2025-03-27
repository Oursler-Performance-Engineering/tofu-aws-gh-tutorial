# You cannot create a new backend by simply defining this and then
# immediately proceeding to "terraform apply". The S3 backend must
# be bootstrapped according to the simple yet essential procedure in
# https://github.com/cloudposse/terraform-aws-tfstate-backend#usage
module "terraform_state_backend" {
  source  = "cloudposse/tfstate-backend/aws"
  version = "v1.5.0"

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

  source  = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-provider"
  version = "v5.54.0"
}

# These permissions are documented here https://opentofu.org/docs/language/settings/backends/s3/
data "aws_iam_policy_document" "backend_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    # This could be further scoped down with a predermined bucket name
    # for the web stack's backend we'll create later.
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:PutObject"
    ]
    # This could be further scoped down with a predermined bucket name
    # for the web stack's backend we'll create later.
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem"
    ]
    # This could be further scoped down with a predermined table name
    # for the web stack's backend we'll create later.
    resources = ["*"]
  }
}

resource "aws_iam_policy" "backend_policy" {
  name   = "tf-backend-policy"
  policy = data.aws_iam_policy_document.backend_policy.json
}

module "iam_github_write_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-role"
  version = "v5.54.0"

  name = "github-write-role"

  subjects = ["justin-o12/tofu-gh-example:ref:refs/heads/main"]

  policies = {
    AmazonDynamoDBFullAccess = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
    AmazonEC2FullAccess      = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
    AmazonS3FullAccess       = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
    AmazonVPCFullAccess      = "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
    tf-backend-policy        = aws_iam_policy.backend_policy.arn
  }
}

module "iam_github_read_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-role"
  version = "v5.54.0"

  name = "github-read-role"

  subjects = ["justin-o12/tofu-gh-example:*"]

  policies = {
    ReadOnlyAccess    = "arn:aws:iam::aws:policy/ReadOnlyAccess"
    tf-backend-policy = aws_iam_policy.backend_policy.arn
  }
}
