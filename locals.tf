// -----------------------------------------------------------------------------
// Local Configuration
// -----------------------------------------------------------------------------
locals {
  aws_region         = var.aws_region
  environment        = var.environment
  project_name       = "confluxdb"
  component_name     = "confluxdb-infra"
  owner_name         = "Michael"
  cost_center_name   = "confluxdb-prod"
  # Use a single Availability Zone to reduce baseline cost
  availability_zones = [data.aws_availability_zones.available.names[0]]
  vpc_cidr           = "10.0.0.0/16"
  github_org         = "michael-esdege"
  github_repo        = "confluxdb"

  ecr_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1,
      description  = "Expire untagged images older than 14 days",
      action = {
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

}
