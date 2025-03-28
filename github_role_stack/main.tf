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
    AmazonEC2FullAccess      = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
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
