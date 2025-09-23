# Output values that expose important resource identifiers.
# Surfaces key identifiers for networking, ECS services, ECR repositories, and IAM roles used by ConfluxDB automation.

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

output "ecs_worker_task_family" {
  description = "Task definition family name for the worker (use in CI)"
  value       = aws_ecs_task_definition.worker.family
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

output "agent_ci_role_arn" {
  description = "IAM Role ARN for the Dagster agent repo CI (assume via GitHub OIDC)"
  value       = aws_iam_role.app_repo_agent_ci.arn
}

output "worker_ci_role_arn" {
  description = "IAM Role ARN for the worker code repo CI (assume via GitHub OIDC)"
  value       = aws_iam_role.app_repo_worker_ci.arn
}

output "ecr_dagster_repository_url" {
  description = "ECR repository URL for Dagster agent image"
  value       = module.ecr_dagster.repository_url
}

output "ecr_confluxdb_code_repository_url" {
  description = "ECR repository URL for worker code image"
  value       = module.ecr_confluxdb_code.repository_url
}

output "service_discovery_namespace_id" {
  description = "Cloud Map private DNS namespace ID for Dagster ECS code servers"
  value       = aws_service_discovery_private_dns_namespace.dagster.id
}

output "service_discovery_namespace_name" {
  description = "Cloud Map private DNS namespace name"
  value       = aws_service_discovery_private_dns_namespace.dagster.name
}
