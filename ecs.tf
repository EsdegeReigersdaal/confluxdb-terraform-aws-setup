############################################
# ECS Cluster, Dagster Agent, and Worker TD
############################################

locals {
  # If a managed secret for the agent token exists, automatically pass it to the container
  dagster_agent_token_secret_entries = length(aws_secretsmanager_secret.dagster_agent_token) > 0 ? [
    {
      name      = "DAGSTER_CLOUD_AGENT_TOKEN"
      valueFrom = aws_secretsmanager_secret.dagster_agent_token[0].arn
    }
  ] : []

  # Managed secrets created via variables for agent/worker
  agent_managed_secret_entries  = [for k, s in aws_secretsmanager_secret.agent_managed : { name = k, valueFrom = s.arn }]
  worker_managed_secret_entries = [for k, s in aws_secretsmanager_secret.worker_managed : { name = k, valueFrom = s.arn }]
}

resource "aws_ecs_cluster" "cluster" {
  name = "${local.project_name}-${local.environment}-ecs"
}

# CloudWatch logs for the agent container
resource "aws_cloudwatch_log_group" "ecs_agent" {
  name              = "/aws/ecs/${local.project_name}-${local.environment}/agent"
  retention_in_days = var.dagster_agent_log_retention_days
}

# Dagster agent task definition (service)
resource "aws_ecs_task_definition" "dagster_agent" {
  family                   = "${local.project_name}-${local.environment}-dagster-agent"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.dagster_agent_cpu
  memory                   = var.dagster_agent_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.dagster_agent_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "dagster-agent"
      image     = "${module.ecr_dagster.repository_url}:${var.dagster_agent_image_tag}"
      essential = true
      cpu       = var.dagster_agent_cpu
      memory    = var.dagster_agent_memory

      environment = [for k, v in var.dagster_agent_env : { name = k, value = v }]
      secrets = concat(
        [for s in var.dagster_agent_secrets : { name = s.name, valueFrom = s.value_from }],
        local.dagster_agent_token_secret_entries,
        local.agent_managed_secret_entries
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_agent.name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
      readonlyRootFilesystem = true
    }
  ])
}

# Dagster agent ECS service
resource "aws_ecs_service" "dagster_agent" {
  name                   = "${local.project_name}-${local.environment}-dagster-agent"
  cluster                = aws_ecs_cluster.cluster.id
  task_definition        = aws_ecs_task_definition.dagster_agent.arn
  desired_count          = var.dagster_agent_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [module.app_sg.security_group_id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# CloudWatch logs for worker tasks
resource "aws_cloudwatch_log_group" "ecs_worker" {
  name              = "/aws/ecs/${local.project_name}-${local.environment}/worker"
  retention_in_days = var.worker_log_retention_days
}

# Ephemeral worker task definition used by the agent via RunTask
resource "aws_ecs_task_definition" "worker" {
  family                   = "${local.project_name}-${local.environment}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.confluxdb_worker_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "worker"
      image     = "${module.ecr_confluxdb_code.repository_url}:${var.confluxdb_code_image_tag}"
      essential = true
      cpu       = var.worker_cpu
      memory    = var.worker_memory

      environment = [for k, v in var.worker_env : { name = k, value = v }]
      secrets = concat(
        [for s in var.worker_secrets : { name = s.name, valueFrom = s.value_from }],
        local.worker_managed_secret_entries
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_worker.name
          awslogs-region        = local.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
      readonlyRootFilesystem = true
    }
  ])
}
