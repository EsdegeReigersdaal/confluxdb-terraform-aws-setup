variable "aws_region" {
  description = "The AWS region to create resources in."
  type        = string
  default     = "eu-west-3"
}

variable "project_prefix" {
  description = "Unique prefix for resource names."
  type        = string
  default     = "confluxdb"
}