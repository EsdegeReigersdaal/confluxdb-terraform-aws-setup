variable "aws_region" {
  description = "The AWS region for the environment."
  type        = string
}

variable "db_username" {
  description = "The username for the RDS database."
  type        = string
  sensitive   = true
}

variable "dagster_agent_token" {
  description = "The token for the Dagster+ agent."
  type        = string
  sensitive   = true
}