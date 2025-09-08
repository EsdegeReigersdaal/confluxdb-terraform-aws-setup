provider "aws" {
  region = local.aws_region

  default_tags {
    tags = {
      "Environment" = local.environment
      "Project"     = local.project_name
      "ManagedBy"   = "Terraform"
      "Component"   = local.component_name
      "Owner"       = local.owner_name
      "CostCenter"  = local.cost_center_name
      "Terraform"   = "true"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}