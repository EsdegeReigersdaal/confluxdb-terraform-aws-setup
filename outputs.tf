# -----------------------------------------------------------------------------
# Root Outputs
# -----------------------------------------------------------------------------
output "vpc_id" {
  description = "The ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The primary CIDR block of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "public_subnets" {
  description = "List of IDs of public subnets."
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "List of IDs of private subnets."
  value       = module.vpc.private_subnets
}

output "database_subnets" {
  description = "List of IDs of database subnets."
  value       = module.vpc.database_subnets
}

output "nat_public_ips" {
  description = "List of public Elastic IP addresses assigned to the NAT Gateways."
  value       = module.vpc.nat_public_ips
}

output "default_security_group_id" {
  description = "The ID of the default security group for the VPC."
  value       = module.vpc.default_security_group_id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.cluster.name
}

output "ecs_dagster_agent_service_name" {
  description = "Name of the Dagster agent ECS service"
  value       = aws_ecs_service.dagster_agent.name
}

output "ecs_worker_task_definition_arn" {
  description = "ARN of the worker task definition used for ephemeral runs"
  value       = aws_ecs_task_definition.worker.arn
}

output "app_security_group_id" {
  description = "Security group ID used by agent and worker tasks"
  value       = module.app_sg.security_group_id
}

output "dagster_agent_token_secret_arn" {
  description = "ARN of the managed Dagster agent token secret (if created)"
  value       = try(aws_secretsmanager_secret.dagster_agent_token[0].arn, null)
}

output "rds_master_user_secret_arn" {
  description = "ARN of the RDS master user secret (from module.rds)"
  value       = module.rds.db_instance_master_user_secret_arn
}
