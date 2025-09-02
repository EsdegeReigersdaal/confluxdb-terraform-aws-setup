provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      "Environment" = "production"
      "Project"     = "ConfluxDB"
      "ManagedBy"   = "Terraform"
      "Component"   = "terraform-backend"
      "Owner"       = "data-platform-team"
      "CostCenter"  = "confluxdb-prod"
    }
  }
}