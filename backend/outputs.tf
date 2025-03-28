output "backend_bucket" {
  value = module.terraform_state_backend.s3_bucket_id
}

output "backend_table" {
  value = module.terraform_state_backend.dynamodb_table_name
}
