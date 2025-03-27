terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    region  = "us-east-2"
    bucket  = "example-dev-web-stack-state"
    key     = "terraform.tfstate"
    profile = ""
    encrypt = "true"

    dynamodb_table = "example-dev-web-stack-state-lock"
  }
}
