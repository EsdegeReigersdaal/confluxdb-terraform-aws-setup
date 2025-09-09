# -----------------------------------------------------------------------------
# ECR repositories
# -----------------------------------------------------------------------------
module "ecr_confluxdb_code" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "3.0.1"

  repository_name                 = "${local.project_name}-${local.environment}-confluxdb-code"
  repository_image_tag_mutability = "IMMUTABLE"
  repository_lifecycle_policy     = local.ecr_lifecycle_policy

  repository_image_scan_on_push = true
}

# Repository for Dagster agent image
module "ecr_dagster" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "3.0.1"

  repository_name                 = "${local.project_name}-${local.environment}-dagster-agent"
  repository_image_tag_mutability = "IMMUTABLE"
  repository_lifecycle_policy     = local.ecr_lifecycle_policy
  repository_image_scan_on_push   = true
}
