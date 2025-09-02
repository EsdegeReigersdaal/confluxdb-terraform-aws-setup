terraform {
  # Specifies the required version of Terraform to run this configuration.
  # Using the "~>" operator locks the major and minor versions while allowing
  # for patch-level updates, which is a best practice for stability.
  required_version = "~> 1.8.0"

  required_providers {
    # Defines the required AWS provider and pins its version. This ensures
    # that your infrastructure code is not affected by incompatible changes
    # in newer provider versions.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Defines the Random provider, which is essential for generating
    # secure, dynamic secrets like the RDS master password, avoiding
    # hardcoded credentials.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}