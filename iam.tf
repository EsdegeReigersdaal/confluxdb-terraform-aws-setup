resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]


  tags = {
    Name = "GitHub Actions OIDC Provider"
  }
}

resource "aws_iam_role" "github_actions" {
  name = "${local.project_name}-${local.environment}-GithubActionsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:sub" = "repo:${local.github_org}/${local.github_repo}:ref:refs/heads/main"
          }
        }
      }
    ]
  })
  tags = {
    Name = "Github Actions role for ConfluxDB"
  }
}

resource "aws_iam_policy" "github_actions_policy" {
  name        = "${local.project_name}-${local.environment}-GithubActionsPolicy"
  description = "Policy for Github Actions to deploy ConfluxDB on ECS."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService"
        ]
        Resource = module.ecs.services["dagster-ui"].arn
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource  = module.ecs.task_execution_role_arn
        Condition = {
          "StringEquals" = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_attach" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_policy.arn
}

resource "aws_iam_policy" "read_rds_secret" {
  name        = "${local.project_name}-${local.environment}-read-rds-secret-policy"
  description = "Allows reading the RDS secret from Secrets Manager"

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action   = ["secretsmanager:GetSecretValue"]
        Effect   = "Allow"
        Resource = module.rds.master_user_secret.arn
      },
    ]
  })
}