# Shared provider configuration.
# Configures the AWS provider with shared tags and account metadata.

# Applies standard tags and region settings to every AWS resource.
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

# Retrieves active availability zones to inform subnet placement.
data "aws_availability_zones" "available" {
  state = "available"
}

# Exposes the AWS account ID for tagging and naming helpers.
data "aws_caller_identity" "current" {}
