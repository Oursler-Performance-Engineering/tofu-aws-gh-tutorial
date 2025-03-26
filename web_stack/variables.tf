variable "region" {
  description = "AWS region"
  type = string
  default = "us-east-2"
}

variable "cidr" {
  description = "VPC CIDR"
  type = string
  default = "10.0.0.0/16"
}

variable "num_azs" {
  description = "Desired number of AZs to use in a region."
  type        = number
  default     = 1
}
