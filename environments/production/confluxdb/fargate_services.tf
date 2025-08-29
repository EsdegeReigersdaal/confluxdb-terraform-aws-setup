# environments/production/confluxdb/fargate_services.tf

# ==============================================================================
# SHARED INFRASTRUCTURE (ECR, ECS Cluster, Execution Role)
# ==============================================================================

# --- ECR Repositories to store Docker images ---
resource "aws_ecr_repository" "runner_ecr" {
  name = "confluxdb-github-runner"
}

resource "aws_ecr_repository" "dagster_agent_ecr" {
  name = "confluxdb-dagster-agent"
}

# --- ECS Cluster to run all services and tasks ---
resource "aws_ecs_cluster" "main_cluster" {
  name = "confluxdb-main-cluster"
}

# --- Shared IAM Role for ECS Task Execution ---
# This role is used by the ECS agent to pull container images and send logs.
# It can be shared by both the runner and the agent tasks.
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "confluxdb-ecs-task-execution-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


# ==============================================================================
# DAGSTER AGENT: PERSISTENT SERVICE
# ==============================================================================

# --- IAM Role for the Dagster Agent Task ---
# Defines the permissions for the agent container itself.
resource "aws_iam_role" "dagster_agent_task_role" {
  name = "confluxdb-dagster-agent-task-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# Policy allowing the agent to fetch its token from Secrets Manager
resource "aws_iam_role_policy" "dagster_agent_secrets_policy" {
  name = "dagster-agent-secrets-access"
  role = aws_iam_role.dagster_agent_task_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = "secretsmanager:GetSecretValue",
      Effect   = "Allow",
      Resource = aws_secretsmanager_secret.dagster_agent_token.arn
    }]
  })
}

# --- ECS Task Definition for the Dagster Agent ---
resource "aws_ecs_task_definition" "dagster_agent_task" {
  family                   = "dagster-agent-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"  # 0.25 vCPU
  memory                   = "512"  # 0.5 GB
  task_role_arn            = aws_iam_role.dagster_agent_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "dagster-agent"
    image     = "${aws_ecr_repository.dagster_agent_ecr.repository_url}:latest"
    secrets = [
      {
        name      = "DAGSTER_CLOUD_AGENT_TOKEN"
        valueFrom = aws_secretsmanager_secret.dagster_agent_token.arn
      }
    ]
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        "awslogs-group"         = "/ecs/dagster-agent",
        "awslogs-region"        = var.aws_region,
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# --- ECS Service for the Dagster Agent ---
# This ensures the Dagster Agent is always running.
resource "aws_ecs_service" "dagster_agent_service" {
  name            = "dagster-agent-service"
  cluster         = aws_ecs_cluster.main_cluster.id
  task_definition = aws_ecs_task_definition.dagster_agent_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1 # Ensures one agent is always running

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.fargate_sg.id]
  }

  depends_on = [aws_iam_role.dagster_agent_task_role]
}


# ==============================================================================
# GITHUB RUNNER: EPHEMERAL TASK
# ==============================================================================

# --- IAM Role for the GitHub Runner Task ---
# Defines permissions for the runner container itself. Can be expanded
# if the runner needs to interact with other AWS services.
resource "aws_iam_role" "ecs_task_role" {
  name = "confluxdb-ecs-task-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# --- ECS Task Definition for the GitHub Runner ---
resource "aws_ecs_task_definition" "runner_task" {
  family                   = "github-runner-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024" # 1 vCPU
  memory                   = "2048" # 2 GB
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "runner"
    image     = "${aws_ecr_repository.runner_ecr.repository_url}:latest"
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        "awslogs-group"         = "/ecs/github-runner-task",
        "awslogs-region"        = var.aws_region,
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  depends_on = [aws_iam_role_policy_attachment.ecs_task_execution_role_policy]
}