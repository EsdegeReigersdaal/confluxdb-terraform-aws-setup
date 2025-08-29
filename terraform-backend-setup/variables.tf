variable "aws_region" {
  description = "The AWS region to create resources in."
  type        = string
  default     = "eu-west-1"
}

variable "bucket_name" {
  description = "The name of the S3 bucket for Terraform state."
  type        = string
  default     = "confluxdb-prod-tfstate"
}

variable "table_name" {
  description = "The name of the DynamoDB table for state locking."
  type        = string
  default     = "aws_dynamodb_table.tflock.confluxdb"
}