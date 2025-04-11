# Deploying AWS Infrastructure with OpenTofu & GitHub Actions – A Step-by-Step Guide

Justin Oursler, Oursler Performance Engineering

April 1, 2025

## Introduction

This guide is designed for DevOps beginners, cloud engineers, startup developers, and anyone looking to streamline cloud deployments using modern Infrastructure as code (IaC) and continuous integration and continuous deployment (CI/CD) practices.  You will learn how to write a basic AWS infrastructure using OpenTofu and automate that infrastructure using GitHub Actions.

## Setting Up Your Environment

### AWS CLI

There is one initial setup for the OpenTofu backend where you will need to deploy a subset of the infrastructure from your computer rather than with GitHub Actions.  We’ll cover those steps in a later section.  For now, you will need to install AWS’s command line interface (CLI).  Follow the steps on the [AWS documentation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) depending on your OS.  Then, configure your local profile for account access using the following command.

```bash
aws configure
```

### OpenTofu

Follow [OpenTofu’s documentation](https://opentofu.org/docs/intro/install/) to install it depending on your OS.  I suggest using [Homebrew](https://brew.sh/) if you are using macOS or Linux.  Verify the installation with the following command.

```bash
tofu version
```

## Writing the Infrastructure

We will create two different infrastructure stacks using OpenTofu.  The first stack will only manage the [OIDC provider and IAM role for GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services).  We will need to manually manage this stack from our local machine.  The second stack will be the rest of our infrastructure to deploy a VPC and EC2 instance.  We will deploy this stack through GitHub Actions.

**Note:**  The versions used throughout this guide were the latest versions at the time of writing.  You may want to use different versions after referring to the releases and their notes.

### Backend Stack

You can manage [OpenTofu’s state](https://opentofu.org/docs/language/state/) in multiple ways.  This guide will walk you through setting up a remote state in AWS S3.  Yet again, there are a couple ways to set up the state in S3, but I recommend [Cloud Posse’s aws-tfstate-backend module](https://github.com/cloudposse/terraform-aws-tfstate-backend).  Following their directions, create a template file with the following contents.  Create a new directory in the root of your repository called `backend` and put the following resources in `backend/main.tf`.

```hcl
# You cannot create a new backend by simply defining this and then
# immediately proceeding to "terraform apply". The S3 backend must
# be bootstrapped according to the simple yet essential procedure in
# https://github.com/cloudposse/terraform-aws-tfstate-backend#usage
module "terraform_state_backend" {
	source    = "cloudposse/tfstate-backend/aws"
	version 	= "v1.5.0"

	namespace  = "example"
	stage  	   = "dev"
	name   	   = "tofu-github-tutorial"
	attributes = ["state"]

	terraform_backend_config_file_path = "."
	terraform_backend_config_file_name = "backend.tf"
	force_destroy                  	   = false
}
```

You will need to provide unique values for `namespace`, `stage`, and `name`.  These are used to generate the name for the S3 bucket that needs to be globally unique in the AWS partition.  Additionally, you need some initial provider configuration.  I recommend creating the below additional resources.  You could put them all in the same file, but it is a good practice to separate them by function.

`config.tf`

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}
```

`variables.tf`

```hcl
variable "region" {
  description = "AWS region"
	type        = string
	default     = "us-east-2"
}
```

`outputs.tf`

```hcl
output "backend_bucket" {
  value = module.terraform_state_backend.s3_bucket_id
}

output "backend_table" {
  value = module.terraform_state_backend.dynamodb_table_name
}
```

There is an initial, manual process to create the backend.  The following steps will use a local backend (OpenTofu’s default), create the S3 bucket and DynamoDB table in AWS, and finally migrate the state from local to the resources in AWS.

```hcl
tofu init
tofu apply # Here you can review the resources OpenTofu will create.  'yes' will allow the deploymen to continue.
tofu init -force-copy # This migrates the backend from local to AWS

```

You now have a new file, `backend.tf`, that points to the new backend for OpenTofu’s state in AWS.  It should look something like the following example.  Take note of the bucket and table names from this new file or the output of the `apply` (they are the same).  You will use these in the next stacks we create.

```hcl
terraform {
  required_version = ">= 1.0.0"

  backend "s3" {
    region  = "us-east-2"
    bucket  = "example-dev-tofu-github-tutorial-state"
    key     = "terraform.tfstate"
    profile = ""
    encrypt = "true"

    dynamodb_table = "example-dev-tofu-github-tutorial-state-lock"
  }
}
```

### GitHub Role Stack

Create a new directory in the repository’s root called `github_role_stack` to separate this stack from the other infrastructure.

We can now add the IAM OIDC provider and Roles that we will use for GitHub Actions.  Since this is a small stack, I will add everything to `main.tf`.  For larger stacks, it can be helpful to separate resources by service like creating a separate [`iam.tf`](http://iam.tf) file for IAM resources.  You can manage your stacks how you like, but add the following resources in a `.tf` file in the same `github_role_stack` directory.  Replace `<organization>` and `<repo name>` with your GitHub organization or account name and the repository name.

```hcl
module "iam_github_oidc_provider" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-provider"
  version = "v5.54.0"
}

# These permissions are documented here https://opentofu.org/docs/language/settings/backends/s3/
data "aws_iam_policy_document" "backend_policy" {
  statement {
    effect  = "Allow"
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

  subjects = ["<organization>/<repo name>:ref:refs/heads/main"]

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

  subjects = ["<organization>/<repo name>:*"]

  policies = {
    ReadOnlyAccess    = "arn:aws:iam::aws:policy/ReadOnlyAccess"
    tf-backend-policy = aws_iam_policy.backend_policy.arn
  }
}
```

This template creates the OIDC provider for GitHub and two IAM roles.  The first Role, `github-write-role`, is scoped to the `main` branch and given the write access we need to deploy.  The second Role, `github-read-role`, can be used by all branches of the repository but only has read access.  This is a recommended pattern so that tests (e.g. `tofu plan`) can run on other branches without being able to affect the infrastructure until the changes are approved and merged into `main`.

Create a [`backend.tf`](http://backend.tf) file with the bucket and table names from the previous step.  It should look something like the below file with  your stack’s values for `bucket` and `dynamodb_table`.  You need to use a different `key` for each stack.  The one used in this example will work for you.

```hcl
terraform {
  backend "s3" {
    region  = "us-east-2"
    bucket  = "example-dev-tofu-github-tutorial-backend-state"
    key     = "github_role_stack.tfstate"
    profile = ""
    encrypt = "true"

    dynamodb_table = "example-dev-tofu-github-tutorial-state-lock"
  }
}
```

These outputs will be handy:

`outputs.tf`

```hcl
output "write_role_arn" {
  value = module.iam_github_write_role.arn
}

output "read_role_arn" {
  value = module.iam_github_read_role.arn
}
```

We have additional modules to download, so run `tofu init` again to retrieve them and `tofu apply` to deploy.  We now have IAM Roles that we will use in our CI/CD.  Copy the ARNs for the read and write Roles for later.  This is the last time we will need to run `tofu init` and `tofu apply` manually.  From here we will setup and use GitHub Actions to do this.

This is also a good point to clean up your repository according to your organization’s standards.  For my example repository, I added the below `.gitignore` file and pushed the current work to `main`.  This is my repository structure so far:

```bash
tofu-gh-example/
  backend/
    .terraform.lock.hcl
    backend.tf
    config.tf
    main.tf
    outputs.tf
    variables.tf
  github_role_stack/
    .terraform.lock.hcl
    backend.tf
    config.tf
    main.tf
    outputs.tf
    variables.tf
  .gitignore
```

`.gitignore`

```bash
# Local .terraform directories
**/.terraform/*

# .tfstate files
*.tfstate
*.tfstate.*

# Crash log files
crash.log
crash.*.log

# Exclude all .tfvars files, which are likely to contain sensitive data, such as
# password, private keys, and other secrets. These should not be part of version
# control as they are data points which are potentially sensitive and subject
# to change depending on the environment.
*.tfvars
*.tfvars.json

# Ignore override files as they are usually used to override resources locally and so
# are not checked in
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Ignore transient lock info files created by terraform apply
.terraform.tfstate.lock.info

# Include override files you do wish to add to version control using negated pattern
# !example_override.tf

# Include tfplan files to ignore the plan output of command: terraform plan -out=tfplan
# example: *tfplan*

# Ignore CLI configuration files
.terraformrc
terraform.rc
```

### Web Stack

Next, we will create the other stack for the the rest of our infrastructure.  Create a new Git branch, and create a new directory called `web_stack` to separate this stack.  Add the below resources to `web_stack/main.tf` .  Here is a quick overview of the resources we’re adding:

- VPC with a public subnet for the EC2 instance
- Security Group allowing HTTP and ICMP ingress and all egress
- EC2 instance with nginx set up
- Elastic IP (EIP) to give the web instance a public IP

`main.tf`

```yaml
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# This will resolved to the latest AMI of 64-bit Amazon Linux 2.
data "aws_ami" "web_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

locals {
  # This is a fancy way of getting the availability zones of a region rather than having to hardcode them like:
  # ["us-east-2a", "us-east-2b", "us-east-2c"]
  # Hardcoding is never a good idea and the letters at the end are not always consistent.
  azs = [for az_name in slice(data.aws_availability_zones.available.names, 0, min(length(data.aws_availability_zones.available.names), var.num_azs)) : az_name]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  name = "web-vpc"
  cidr = var.cidr

  azs            = local.azs
  public_subnets = [for k, v in module.vpc.azs : cidrsubnet(module.vpc.vpc_cidr_block, 5, k)]
}

resource "aws_security_group" "web_sg" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.web_ami.image_id
  instance_type          = "t2.micro"
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install -y nginx1
              systemctl start nginx
              systemctl enable nginx
              EOF

  tags = {
    Name = "WebServer"
  }
}

resource "aws_eip" "web_eip" {
  instance = aws_instance.web.id
}
```

Additionally, I added the below variables, output, config, and backend.  Again, make sure you put your bucket and table names in `backend.tf`.

`variables.tf`

```yaml
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "num_azs" {
  description = "Desired number of AZs to use in a region."
  type        = number
  default     = 1
}
```

`outputs.tf`

```yaml
output "web_eip" {
  value = aws_eip.web_eip.public_ip
}
```

`config.tf`

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}
```

`backend.tf`

```hcl
terraform {
  backend "s3" {
    region  = "us-east-2"
    bucket  = "example-dev-tofu-github-tutorial-state"
    key     = "web_stack.tfstate"
    profile = ""
    encrypt = "true"

    dynamodb_table = "example-dev-tofu-github-tutorial-state-lock"
  }
}
```

**GitHub Actions**

We will add GitHub Actions and additional infrastructure in a new branch.  This way we can easily see the changes in a pull request (PR).

Add a repository secret called `READ_ROLE_ARN` with a value of the read only role created above for GitHub.  Add a similar secret, `WRITE_ROLE_ARN`, for the write Role.  Additionally, create a repository variable, `AWS_REGION`, with the same region you used in the above stacks.  For example, I would set the variable’s value to `us-east-2` since I left the default value.  Then, create the following GitHub workflow in `.github/workflows/plan.yml`.

```yaml
name: OpenTofu Plan on PR

on:
  pull_request:
    branches:
      - main

permissions:
  id-token: write  # Required for OIDC authentication
  contents: read   # Required to checkout the repository

jobs:
  plan:
    name: Run OpenTofu Plan
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Repository
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2

      - name: Configure AWS Credentials via OIDC
        uses: aws-actions/configure-aws-credentials@ececac1a45f3b08a01d2dd070d28d111c5fe6722 # v4.1.0
        with:
          role-to-assume: ${{ secrets.READ_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}

      - name: Install OpenTofu
        uses: opentofu/setup-opentofu@592200bd4b9bbf4772ace78f887668b1aee8f716 # v1.0.5
        with:
          tofu-version: latest

      - name: Run OpenTofu Plan for web stack
        working-directory: web_stack
        run: |
          tofu init
          tofu plan
```

Commit and push these changes to your branch, and create a PR.  You should be able to watch this new workflow in the Checks tab of the PR and see the plan output with the new resources.  Common problems to look out for are IAM permissions and Actions variables and secrets.

We now have our minimal CI/CD pipeline setup to test our changes through GitHub Actions.

### Deploy

We want to deploy these changes after a successful merge.  Create the following workflow file.

`.github/workflows/deploy.yml`

```yaml
name: Deploy AWS Infrastructure

on:
  push:
    branches:
      - main

permissions:
  id-token: write  # Required for OIDC authentication
  contents: read   # Required to checkout the repository

jobs:
  deploy:
    name: Deploy Infrastructure
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Repository
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2

      - name: Configure AWS Credentials via OIDC
        uses: aws-actions/configure-aws-credentials@ececac1a45f3b08a01d2dd070d28d111c5fe6722 # v4.1.0
        with:
          role-to-assume: ${{ secrets.WRITE_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}

      - name: Install OpenTofu
        uses: opentofu/setup-opentofu@592200bd4b9bbf4772ace78f887668b1aee8f716 # v1.0.5
        with:
          tofu_version: latest

      - name: Deploy Web Stack
        working-directory: web_stack
        run: |
          tofu init
          tofu apply -auto-approve
```

Update and merge the PR to deploy the infrastructure.

Navigate to the Actions menu of your repository.  You should see a new workflow run for `Deploy AWS Infrastructure` on `main` that the merge triggered.  Look at the bottom of the `Deploy Web Stack` output and you should see the value of the `web_eip` output.  Use this IP to validate the deployment and nginx start are successful by navigating or curling `http://<web_eip>:80`.  You should see the default nginx page.

## Cleanup

We will destroy the stacks in reverse order:  web, GitHub Role, and then backend.  Make the following changes to the `plan.yml` and `deplo.yml` workflows.  These changes will allow us to destroy the web stack through CI/CD.

```diff
diff --git a/.github/workflows/deploy.yml b/.github/workflows/deploy.yml
index 10e4578..9d91ab4 100644
--- a/.github/workflows/deploy.yml
+++ b/.github/workflows/deploy.yml
@@ -33,4 +33,4 @@ jobs:
         working-directory: web_stack
         run: |
           tofu init
-          tofu apply -auto-approve
+          tofu apply -destroy -auto-approve
diff --git a/.github/workflows/plan.yml b/.github/workflows/plan.yml
index f2b74e4..27011f6 100644
--- a/.github/workflows/plan.yml
+++ b/.github/workflows/plan.yml
@@ -33,4 +33,4 @@ jobs:
         working-directory: web_stack
         run: |
           tofu init
-          tofu plan
+          tofu plan -destroy
```

Push these changes through the PR and merge process to destroy the web stack.

Destroy the GitHub Role stack by running `tofu apply` in the `github_role_stack` directory.

Apply the following change to `backend/main.tf` to begin the process to destroy the backend stack.

```diff
--- a/backend/main.tf
+++ b/backend/main.tf
@@ -11,7 +11,7 @@ module "terraform_state_backend" {
   name       = "oursler-backend"
   attributes = ["state"]
 
-  terraform_backend_config_file_path = "."
+  terraform_backend_config_file_path = ""
   terraform_backend_config_file_name = "backend.tf"
-  force_destroy                      = false
+  force_destroy                      = true
 }
```

Then, run the following commands in the `backend` directory.

```bash
tofu apply -target module.terraform_state_backend -auto-approve
tofu init -force-copy
tofu destroy
```

## Conclusion

By following this guide, you successfully:

- Set up a backend in AWS for OpenTofu
- Deployed IAM resources to enable GitHub Actions
- Used OpenTofu and GitHub Actions to provision infrastructure in AWS

The web stack you deployed with an EC2 instance and nginx is just a minimal example to demonstrate Infrastructure as Code (IaC) and CI/CD. You can easily swap it out for any infrastructure you need to deploy on AWS.

I’d love to hear your feedback or answer any questions. Feel free to [connect with me on LinkedIn](https://www.linkedin.com/in/justinoursler/). If you found this guide helpful and want more content like this, let me know what topics you’d like to see next!
