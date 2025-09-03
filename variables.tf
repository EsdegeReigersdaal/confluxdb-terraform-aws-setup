variable "aws_region" {
  description = "The AWS region where the backend resources will be created."
  type        = string
  default     = "eu-west-1"
}

variable "s3_bucket_name" {
  description = "The globally unique name for the S3 bucket used for Terraform state."
  type        = string
}
