terraform {
  backend "s3" {
    bucket         = "confluxdb-tfstate-60cqjkdw"
    key            = "production/data-platform/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "confluxdb-terraform-state-lock"
    encrypt        = true
  }
}