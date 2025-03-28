output "write_role_arn" {
  value = module.iam_github_write_role.arn
}

output "read_role_arn" {
  value = module.iam_github_read_role.arn
}
