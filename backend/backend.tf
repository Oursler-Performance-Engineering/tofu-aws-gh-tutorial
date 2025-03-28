terraform {
  required_version = ">= 1.0.0"

  backend "s3" {
    region  = "us-east-2"
    bucket  = "example-dev-oursler-backend-state"
    key     = "terraform.tfstate"
    profile = ""
    encrypt = "true"

    dynamodb_table = "example-dev-oursler-backend-state-lock"
  }
}
