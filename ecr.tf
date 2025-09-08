# -----------------------------------------------------------------------------
# ECR (Elastic Container Registry) Repositories
# Creates separate repositories for each service in the data platform.
# -----------------------------------------------------------------------------
module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"

  repositories = {
    dagster = {
      name                 = "${local.project_name}-${local.environment}-dagster"
      scan_on_push         = true
      image_tag_mutability = "IMMUTABLE"

      lifecycle_policy = jsonencode({
        rules = [{
          rulePriority = 1,
          description  = "Keep last 30 images",
          action       = {
            type = "expire"
          },
          selection = {
            tagStatus   = "untagged",
            countType   = "sinceImagePushed",
            countUnit   = "days",
            countNumber = 14
          }
        }]
      })

      tags = {
        Service = "Dagster"
      }
    },
    meltano = {
      name                 = "${local.project_name}-${local.environment}-meltano"
      scan_on_push         = true
      image_tag_mutability = "IMMUTABLE"

      lifecycle_policy = jsonencode({
        rules = [{
          rulePriority = 1,
          description  = "Keep last 30 images",
          action       = {
            type = "expire"
          },
          selection = {
            tagStatus   = "untagged",
            countType   = "sinceImagePushed",
            countUnit   = "days",
            countNumber = 14
          }
        }]
      })

      tags = {
        Service = "Meltano"
      }
    },
    sqlmesh = {
      name                 = "${local.project_name}-${local.environment}-sqlmesh"
      scan_on_push         = true
      image_tag_mutability = "IMMUTABLE"

      lifecycle_policy = jsonencode({
        rules = [{
          rulePriority = 1,
          description  = "Keep last 30 images",
          action       = {
            type = "expire"
          },
          selection = {
            tagStatus   = "untagged",
            countType   = "sinceImagePushed",
            countUnit   = "days",
            countNumber = 14
          }
        }]
      })

      tags = {
        Service = "SQLMesh"
      }
    }
  }

  tags = {
    Project     = local.project_name
    Environment = local.environment
  }
}