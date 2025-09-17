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
          "ecs:CreateService",
          "ecs:DeleteService",
          "ecs:DescribeClusters",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks",
          "ecs:ListAccountSettings",
          "ecs:ListServices",
          "ecs:ListTasks",
          "ecs:RegisterTaskDefinition",
          "ecs:RunTask",
          "ecs:StopTask",
          "ecs:TagResource",
          "ecs:UpdateService"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeRouteTables"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:ListTagsForResource",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:ListSecrets",
          "tag:GetResources"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:GetLogEvents"]
        Resource = format("%s:log-stream:*", aws_cloudwatch_log_group.ecs_agent.arn)
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
      },
      {
        Effect = "Allow",
        Action = [
          "servicediscovery:ListServices",
          "servicediscovery:ListTagsForResource",
          "servicediscovery:ListInstances",
          "servicediscovery:DeregisterInstance",
          "servicediscovery:GetOperation",
          "servicediscovery:DeleteService"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "servicediscovery:GetNamespace",
          "servicediscovery:CreateService",
          "servicediscovery:TagResource"
        ],
        Resource = [
          aws_service_discovery_private_dns_namespace.dagster.arn,
          "arn:aws:servicediscovery:${local.aws_region}:${data.aws_caller_identity.current.account_id}:service/*"
        ]
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

resource "aws_iam_role_policy" "worker_agent_token_secret_access" {
  count = length(aws_secretsmanager_secret.dagster_agent_token) > 0 ? 1 : 0

  name = "worker-agent-token-secret-access"
  role = aws_iam_role.confluxdb_worker_task_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = aws_secretsmanager_secret.dagster_agent_token[0].arn
      }
    ]
  })
}

# Optional: attach additional managed policies to the worker task role (e.g., S3 access)
resource "aws_iam_role_policy_attachment" "worker_attach" {
  for_each   = { for arn in var.worker_task_role_policy_arns : arn => arn }
  role       = aws_iam_role.confluxdb_worker_task_role.name
  policy_arn = each.value
}

################################################################################
# SECTION 3: CI ROLES FOR APP REPOS (Agent + Worker)
################################################################################

# Trust policy helpers
data "aws_iam_policy_document" "oidc_assume_agent" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_org}/${var.github_agent_repo}:ref:refs/heads/${var.github_ci_branch}"]
    }
  }
}

data "aws_iam_policy_document" "oidc_assume_worker" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_org}/${var.github_worker_repo}:ref:refs/heads/${var.github_ci_branch}"]
    }
  }
}

# Role assumed by the Dagster Agent image repo CI to push to ECR and deploy ECS
resource "aws_iam_role" "app_repo_agent_ci" {
  name               = "${local.project_name}-${local.environment}-agent-ci-role"
  assume_role_policy = data.aws_iam_policy_document.oidc_assume_agent.json
  description        = "CI role for agent repo to push ECR and deploy ECS service"
}

# Role assumed by the Worker code image repo CI to push to ECR and register TDs
resource "aws_iam_role" "app_repo_worker_ci" {
  name               = "${local.project_name}-${local.environment}-worker-ci-role"
  assume_role_policy = data.aws_iam_policy_document.oidc_assume_worker.json
  description        = "CI role for worker repo to push ECR and register ECS task defs"
}

# ---------------------------
# Agent CI permissions
# ---------------------------

resource "aws_iam_policy" "agent_ci_ecr_push" {
  name        = "${local.project_name}-${local.environment}-agent-ci-ecr-push"
  description = "Allow pushing to the Dagster agent ECR repo"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["ecr:GetAuthorizationToken"],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:BatchGetImage"
        ],
        Resource = [
          module.ecr_dagster.repository_arn,
          "${module.ecr_dagster.repository_arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "agent_ci_ecs_deploy" {
  name        = "${local.project_name}-${local.environment}-agent-ci-ecs-deploy"
  description = "Allow registering task defs and updating the Dagster agent service"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecs:DescribeClusters",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:ListTaskDefinitions"
        ],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["ecs:UpdateService"],
        Resource = aws_ecs_service.dagster_agent.arn
      }
    ]
  })
}

resource "aws_iam_policy" "agent_ci_passrole" {
  name        = "${local.project_name}-${local.environment}-agent-ci-passrole"
  description = "Allow passing required IAM roles when registering TDs"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["iam:PassRole"],
        Resource = [
          aws_iam_role.ecs_task_execution_role.arn,
          aws_iam_role.dagster_agent_task_role.arn
        ],
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "agent_ci_attach_ecr" {
  role       = aws_iam_role.app_repo_agent_ci.name
  policy_arn = aws_iam_policy.agent_ci_ecr_push.arn
}

resource "aws_iam_role_policy_attachment" "agent_ci_attach_ecs" {
  role       = aws_iam_role.app_repo_agent_ci.name
  policy_arn = aws_iam_policy.agent_ci_ecs_deploy.arn
}

resource "aws_iam_role_policy_attachment" "agent_ci_attach_passrole" {
  role       = aws_iam_role.app_repo_agent_ci.name
  policy_arn = aws_iam_policy.agent_ci_passrole.arn
}

# ---------------------------
# Worker CI permissions
# ---------------------------

resource "aws_iam_policy" "worker_ci_ecr_push" {
  name        = "${local.project_name}-${local.environment}-worker-ci-ecr-push"
  description = "Allow pushing to the worker code ECR repo"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["ecr:GetAuthorizationToken"],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:BatchGetImage"
        ],
        Resource = [
          module.ecr_confluxdb_code.repository_arn,
          "${module.ecr_confluxdb_code.repository_arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "worker_ci_register_td" {
  name        = "${local.project_name}-${local.environment}-worker-ci-register-td"
  description = "Allow describing and registering worker task definitions"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:ListTaskDefinitions"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "worker_ci_passrole" {
  name        = "${local.project_name}-${local.environment}-worker-ci-passrole"
  description = "Allow passing required IAM roles when registering worker TDs"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["iam:PassRole"],
        Resource = [
          aws_iam_role.ecs_task_execution_role.arn,
          aws_iam_role.confluxdb_worker_task_role.arn
        ],
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "worker_ci_agent_token_secret_access" {
  count = length(aws_secretsmanager_secret.dagster_agent_token) > 0 ? 1 : 0

  name        = "${local.project_name}-${local.environment}-worker-ci-agent-token-secret"
  description = "Allow worker CI to read the Dagster agent token secret"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = aws_secretsmanager_secret.dagster_agent_token[0].arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "worker_ci_attach_agent_token_secret" {
  count = length(aws_secretsmanager_secret.dagster_agent_token) > 0 ? 1 : 0

  role       = aws_iam_role.app_repo_worker_ci.name
  policy_arn = aws_iam_policy.worker_ci_agent_token_secret_access[0].arn
}

resource "aws_iam_role_policy_attachment" "worker_ci_attach_ecr" {
  role       = aws_iam_role.app_repo_worker_ci.name
  policy_arn = aws_iam_policy.worker_ci_ecr_push.arn
}

resource "aws_iam_role_policy_attachment" "worker_ci_attach_td" {
  role       = aws_iam_role.app_repo_worker_ci.name
  policy_arn = aws_iam_policy.worker_ci_register_td.arn
}

resource "aws_iam_role_policy_attachment" "worker_ci_attach_passrole" {
  role       = aws_iam_role.app_repo_worker_ci.name
  policy_arn = aws_iam_policy.worker_ci_passrole.arn
}
