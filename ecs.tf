# ECS orchestration resources.
# Configures the ECS cluster, Dagster agent service, and worker tasks that run ConfluxDB workloads.

locals {
  # Injects the optional Dagster agent token secret whenever Terraform provisions it.
  dagster_agent_token_secret_entries = length(aws_secretsmanager_secret.dagster_agent_token) > 0 ? [
    {
      name      = "DAGSTER_CLOUD_AGENT_TOKEN"
      valueFrom = aws_secretsmanager_secret.dagster_agent_token[0].arn
    }
  ] : []

  # Converts Terraform-managed secrets into the ECS secrets format.
  agent_managed_secret_entries = [for k, s in aws_secretsmanager_secret.agent_managed : { name = k, valueFrom = s.arn }]

  # Seeds the agent and workers with shared Dagster Cloud identifiers.
  dagster_base_env = {
    DAGSTER_CLOUD_ORGANIZATION = var.dagster_cloud_organization
    DAGSTER_CLOUD_DEPLOYMENT   = var.dagster_cloud_deployment
  }
  dagster_cloud_url_trimmed = var.dagster_cloud_url == null ? null : trimsuffix(var.dagster_cloud_url, "/")
  dagster_url_env           = var.dagster_cloud_url != null && var.dagster_cloud_url != "" ? { DAGSTER_CLOUD_URL = var.dagster_cloud_url } : {}
  dagster_api_env           = local.dagster_cloud_url_trimmed != null && local.dagster_cloud_url_trimmed != "" ? { DAGSTER_CLOUD_API_URL = local.dagster_cloud_url_trimmed } : {}
  dagster_branch_env        = { DAGSTER_CLOUD_BRANCH_DEPLOYMENTS = tostring(var.dagster_cloud_branch_deployments) }

  # Sets a writable DAGSTER_HOME mount so the agent can persist runtime state.
  dagster_home_env = { DAGSTER_HOME = "/opt/dagster/dagster_home" }

  # Exposes the networking and IAM details the agent needs to launch worker tasks.
  dagster_agent_ecs_env = {
    DAGSTER_ECS_CLUSTER              = aws_ecs_cluster.cluster.name
    DAGSTER_ECS_SUBNET_1             = module.vpc.private_subnets[0]
    DAGSTER_ECS_SUBNET_2             = module.vpc.private_subnets[1]
    DAGSTER_ECS_SECURITY_GROUP       = module.app_sg.security_group_id
    DAGSTER_ECS_EXECUTION_ROLE_ARN   = aws_iam_role.ecs_task_execution_role.arn
    DAGSTER_ECS_TASK_ROLE_ARN        = aws_iam_role.confluxdb_worker_task_role.arn
    DAGSTER_ECS_LOG_GROUP            = aws_cloudwatch_log_group.ecs_worker.name
    DAGSTER_ECS_SD_NAMESPACE_ID      = aws_service_discovery_private_dns_namespace.dagster.id
    AWS_REGION                       = local.aws_region
    DAGSTER_CLOUD_AGENT_MEMORY_LIMIT = tostring(var.dagster_agent_memory)
    DAGSTER_CLOUD_AGENT_CPU_LIMIT    = tostring(var.dagster_agent_cpu)
  }

  # Merges base environment values with any user-provided overrides.
  dagster_agent_env_final = merge(
    local.dagster_base_env,
    local.dagster_url_env,
    local.dagster_api_env,
    local.dagster_branch_env,
    local.dagster_home_env,
    local.dagster_agent_ecs_env,
    var.dagster_agent_env,
  )

  # Bootstraps dependencies and writes dagster.yaml before the agent starts.
  dagster_agent_startup_command = <<-EOT
    set -eu
    mkdir -p "$DAGSTER_HOME"
    DAGSTER_TMP="$DAGSTER_HOME/tmp"
    mkdir -p "$DAGSTER_TMP"
    export TMPDIR="$DAGSTER_TMP"
    DAGSTER_VENDOR="$DAGSTER_HOME/vendor"
    mkdir -p "$DAGSTER_VENDOR"
    if [ ! -d "$DAGSTER_VENDOR/boto3" ] || [ ! -d "$DAGSTER_VENDOR/dagster_aws" ]; then
      python -m pip install --no-cache-dir --target "$DAGSTER_VENDOR" boto3 dagster-aws
    fi
    export PYTHONPATH="$DAGSTER_VENDOR:$${PYTHONPATH:-}"
    cat > "$DAGSTER_HOME/dagster.yaml" << YAML
    instance_class:
      module: dagster_cloud
      class: DagsterCloudAgentInstance

    dagster_cloud_api:
      url: "$${DAGSTER_CLOUD_API_URL}"
      agent_token: "$${DAGSTER_CLOUD_AGENT_TOKEN}"
      branch_deployments: true
      deployment: "prod"

    user_code_launcher:
      module: dagster_cloud.workspace.ecs
      class: EcsUserCodeLauncher
      config:
        cluster: $${DAGSTER_ECS_CLUSTER}
        subnets:
          - $${DAGSTER_ECS_SUBNET_1}
          - $${DAGSTER_ECS_SUBNET_2}
        security_group_ids:
          - $${DAGSTER_ECS_SECURITY_GROUP}
        execution_role_arn: $${DAGSTER_ECS_EXECUTION_ROLE_ARN}
        task_role_arn: $${DAGSTER_ECS_TASK_ROLE_ARN}
        log_group: $${DAGSTER_ECS_LOG_GROUP}
        service_discovery_namespace_id: $${DAGSTER_ECS_SD_NAMESPACE_ID}
        launch_type: FARGATE
    YAML
    exec dagster-cloud agent run
  EOT
}

resource "aws_ecs_cluster" "cluster" {
  name = "${local.project_name}-${local.environment}-ecs"
}

# Retains Dagster agent logs in CloudWatch for operational visibility.
resource "aws_cloudwatch_log_group" "ecs_agent" {
  name              = "/aws/ecs/${local.project_name}-${local.environment}/agent"
  retention_in_days = var.dagster_agent_log_retention_days
}

# Defines the Fargate task that hosts the long-running Dagster agent.
resource "aws_ecs_task_definition" "dagster_agent" {
  lifecycle {
    ignore_changes = [container_definitions]
  }
  family                   = "${local.project_name}-${local.environment}-dagster-agent"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.dagster_agent_cpu
  memory                   = var.dagster_agent_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.dagster_agent_task_role.arn

  ephemeral_storage {
    size_in_gib = 21
  }

  # Provides ephemeral storage backing the agent DAGSTER_HOME path.
  volume {
    name = "dagster-home"
  }

  container_definitions = jsonencode([
    {
      name      = "dagster-agent"
      image     = "${module.ecr_dagster.repository_url}:${var.dagster_agent_image_tag}"
      essential = true
      cpu       = var.dagster_agent_cpu
      memory    = var.dagster_agent_memory

      environment = [for k, v in local.dagster_agent_env_final : { name = k, value = v }]
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
      entryPoint = ["bash", "-lc"]
      command    = [replace(local.dagster_agent_startup_command, "\r", "")]
      mountPoints = [
        {
          sourceVolume  = "dagster-home"
          containerPath = "/opt/dagster/dagster_home"
          readOnly      = false
        }
      ]
      readonlyRootFilesystem = true
    }
  ])
}

# Runs the Dagster agent task definition inside the ECS cluster.
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

# Captures Fargate worker task logs for troubleshooting and auditing.
resource "aws_cloudwatch_log_group" "ecs_worker" {
  name              = "/aws/ecs/${local.project_name}-${local.environment}/worker"
  retention_in_days = var.worker_log_retention_days
}







