# ##############################################################################
# SECTION 1: GITHUB ACTIONS OIDC (for CI/CD)
# ##############################################################################
# Provides AWS credentials to the GitHub Actions workflow for deploying code.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  tags           = { Name = "GitHub Actions OIDC Provider" }
}

resource "aws_iam_role" "github_actions" {
  name = "${local.project_name}-${local.environment}-GithubActionsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRoleWithWebIdentity"
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Condition = { StringEquals = { "token.actions.githubusercontent.com:sub" = "repo:${local.github_org}/${local.github_repo}:ref:refs/heads/main" } }
    }]
  })
}

resource "aws_iam_policy" "github_actions_policy" {
  name        = "${local.project_name}-${local.environment}-GithubActionsPolicy"
  description = "Allows Github Actions to push images to ECR and update the Dagster Agent service."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Allows pushing the user-code image to any ECR repository in the account
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_attach" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_policy.arn
}

# ##############################################################################
# SECTION 2: ECS TASK ROLES (Agent + Worker) AND EXECUTION ROLE
# ##############################################################################

locals {
  agent_secret_arns          = [for s in var.dagster_agent_secrets : s.value_from]
  worker_secret_arns         = [for s in var.worker_secrets : s.value_from]
  managed_secret_arns        = length(aws_secretsmanager_secret.dagster_agent_token) > 0 ? [aws_secretsmanager_secret.dagster_agent_token[0].arn] : []
  agent_managed_secret_arns  = [for k, s in aws_secretsmanager_secret.agent_managed : s.arn]
  worker_managed_secret_arns = [for k, s in aws_secretsmanager_secret.worker_managed : s.arn]
  task_exec_secret_arns = concat(
    local.agent_secret_arns,
    local.worker_secret_arns,
    local.managed_secret_arns,
    local.agent_managed_secret_arns,
    local.worker_managed_secret_arns,
  )
}

# Execution role shared by agent + worker tasks
data "aws_iam_policy_document" "ecs_task_exec_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${local.project_name}-${local.environment}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_exec_assume.json
  description        = "ECS task execution role for pulling images, logs, and secrets"
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_managed" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow the execution role to retrieve any injected secrets (if provided)
resource "aws_iam_role_policy" "ecs_task_exec_secrets" {
  count = length(local.task_exec_secret_arns) > 0 ? 1 : 0

  name = "allow-secrets-access"
  role = aws_iam_role.ecs_task_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = local.task_exec_secret_arns
      }
    ]
  })
}

# Task role for the Dagster agent (needs to run ECS tasks and pass roles)
data "aws_iam_policy_document" "dagster_agent_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dagster_agent_task_role" {
  name               = "${local.project_name}-${local.environment}-dagster-agent-task-role"
  assume_role_policy = data.aws_iam_policy_document.dagster_agent_assume.json
  description        = "Task role for Dagster agent to orchestrate ECS RunTask"
}

resource "aws_iam_role_policy" "dagster_agent_ecs_control" {
  name = "ecs-run-task-and-describe"
  role = aws_iam_role.dagster_agent_task_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask",
          "ecs:DescribeTasks",
          "ecs:DescribeTaskDefinition",
          "ecs:ListTasks",
          "ecs:DescribeClusters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.confluxdb_worker_task_role.arn,
          aws_iam_role.ecs_task_execution_role.arn
        ]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      }
    ]
  })
}

# Task role assumed by ephemeral worker tasks
data "aws_iam_policy_document" "worker_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "confluxdb_worker_task_role" {
  name               = "${local.project_name}-${local.environment}-worker-task-role"
  assume_role_policy = data.aws_iam_policy_document.worker_assume.json
  description        = "Task role for ConfluxDB worker (Dagster/Meltano/SQLMesh)"
}

# Optional: attach additional managed policies to the worker task role (e.g., S3 access)
resource "aws_iam_role_policy_attachment" "worker_attach" {
  for_each   = { for arn in var.worker_task_role_policy_arns : arn => arn }
  role       = aws_iam_role.confluxdb_worker_task_role.name
  policy_arn = each.value
}
