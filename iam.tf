# Identity and access management resources.
# Establishes roles, policies, and federated identities for CI/CD and ECS workloads.

# Federates GitHub Actions via OIDC so CI runs can assume AWS roles.
# Grants the Terraform pipeline access to AWS through short-lived credentials.

# Registers the GitHub Actions identity provider for web identity federation.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  tags           = { Name = "GitHub Actions OIDC Provider" }
}

# Defines the role assumed by the Terraform workflow running in GitHub Actions.
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

# Attaches a policy that lets CI push images and update ECS services.
resource "aws_iam_policy" "github_actions_policy" {
  name        = "${local.project_name}-${local.environment}-GithubActionsPolicy"
  description = "Allows Github Actions to push images to ECR and update the Dagster Agent service."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Authorizes GitHub Actions to push images into account ECR repositories.
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

# Defines execution and task roles powering the Dagster agent and worker tasks.

# Aggregates the secret ARNs referenced by the ECS execution and task roles.
locals {
  agent_secret_arns          = [for s in var.dagster_agent_secrets : s.value_from]
  worker_secret_arns         = [for s in var.worker_secrets : s.value_from]
  managed_secret_arns        = length(aws_secretsmanager_secret.dagster_agent_token) > 0 ? [aws_secretsmanager_secret.dagster_agent_token[0].arn] : []
  agent_managed_secret_arns  = [for k, s in aws_secretsmanager_secret.agent_managed : s.arn]
  worker_managed_secret_arns = [for k, s in aws_secretsmanager_secret.worker_managed : s.arn]
  db_iam_user_arn            = "arn:aws:rds-db:${local.aws_region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.rds.db_instance_resource_id}/confluxdb_postgresql"
  task_exec_secret_arns = concat(
    local.agent_secret_arns,
    local.worker_secret_arns,
    local.managed_secret_arns,
    local.agent_managed_secret_arns,
    local.worker_managed_secret_arns
  )
}

# Provides the shared execution role used for image pulls, logging, and secret access.
data "aws_iam_policy_document" "ecs_task_exec_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Creates the execution role that allows ECS tasks to pull images and write logs.
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${local.project_name}-${local.environment}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_exec_assume.json
  description        = "ECS task execution role for pulling images, logs, and secrets"
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_managed" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Adds an inline policy so the execution role can read container secrets when needed.
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

# Defines the trust policy that allows the agent task to assume its IAM role.
data "aws_iam_policy_document" "dagster_agent_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Grants the agent task permissions to run ECS operations and pass IAM roles.
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

resource "aws_iam_role_policy" "dagster_agent_db_connect" {
  name = "dagster-agent-db-connect"
  role = aws_iam_role.dagster_agent_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = local.db_iam_user_arn
      }
    ]
  })
}

# Defines the trust policy that allows worker tasks to assume their IAM role.
data "aws_iam_policy_document" "worker_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Grants worker tasks the permissions needed for data platform activities.
resource "aws_iam_role" "confluxdb_worker_task_role" {
  name               = "${local.project_name}-${local.environment}-worker-task-role"
  assume_role_policy = data.aws_iam_policy_document.worker_assume.json
  description        = "Task role for ConfluxDB worker (Dagster/Meltano/SQLMesh)"
}

resource "aws_iam_role_policy" "worker_db_connect" {
  name = "worker-db-connect"
  role = aws_iam_role.confluxdb_worker_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = local.db_iam_user_arn
      }
    ]
  })
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

# Optionally attaches additional managed policies for worker data access.
resource "aws_iam_role_policy_attachment" "worker_attach" {
  for_each   = { for arn in var.worker_task_role_policy_arns : arn => arn }
  role       = aws_iam_role.confluxdb_worker_task_role.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "jump_host_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jump_host" {
  name               = "${local.project_name}-${local.environment}-jump-role"
  assume_role_policy = data.aws_iam_policy_document.jump_host_assume.json
  description        = "SSM-managed jump host role"
}

resource "aws_iam_instance_profile" "jump_host" {
  name = "${local.project_name}-${local.environment}-jump-profile"
  role = aws_iam_role.jump_host.name
}

resource "aws_iam_role_policy_attachment" "jump_host_ssm" {
  role       = aws_iam_role.jump_host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "jump_host_db_connect" {
  name = "jump-host-db-connect"
  role = aws_iam_role.jump_host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = local.db_iam_user_arn
      }
    ]
  })
}

# Provisions CI roles for the application repositories that publish images and task definitions.

# Supplies helper policy documents used in the role assumption statements.
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
      values = [
        "repo:${local.github_org}/${var.github_agent_repo}:ref:refs/heads/${var.github_ci_branch}",
        "repo:${local.github_org}/${var.github_agent_repo}:environment:prod"
      ]
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
      values = [
        "repo:${local.github_org}/${var.github_worker_repo}:ref:refs/heads/${var.github_ci_branch}",
        "repo:${local.github_org}/${var.github_worker_repo}:environment:prod"
      ]
    }
  }
}

# Defines the CI role for the agent image repository so it can publish artifacts and deploy services.
resource "aws_iam_role" "app_repo_agent_ci" {
  name               = "${local.project_name}-${local.environment}-agent-ci-role"
  assume_role_policy = data.aws_iam_policy_document.oidc_assume_agent.json
  description        = "CI role for agent repo to push ECR and deploy ECS service"
}

# Defines the CI role for the worker code repository to publish images and register task definitions.
resource "aws_iam_role" "app_repo_worker_ci" {
  name               = "${local.project_name}-${local.environment}-worker-ci-role"
  assume_role_policy = data.aws_iam_policy_document.oidc_assume_worker.json
  description        = "CI role for worker repo to push ECR and register ECS task defs"
}

# Attaches policies that grant the agent CI permissions for ECR, ECS updates, and PassRole.

# Allows the agent CI pipeline to publish images to the agent ECR repository.
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

# Permits the agent CI job to update ECS services and describe cluster state.
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

# Allows the agent CI pipeline to pass the ECS execution and task roles during deploys.
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

# Attaches policies that grant the worker CI permissions for ECR publishing and task registration.

# Allows the worker CI pipeline to push code images to its dedicated ECR repository.
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

# Grants the worker CI pipeline ability to register and describe task definitions.
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

# Permits the worker CI pipeline to pass execution and task roles to ECS.
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

# Optionally allows the worker CI pipeline to read the Dagster agent token secret during deploys.
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
