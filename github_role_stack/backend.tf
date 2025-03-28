terraform {
  backend "s3" {
    region  = "us-east-2"
    bucket  = "example-dev-oursler-backend-state"
    key     = "github_role_stack.tfstate"
    profile = ""
    encrypt = "true"

    dynamodb_table = "example-dev-oursler-backend-state-lock"
  }
}
