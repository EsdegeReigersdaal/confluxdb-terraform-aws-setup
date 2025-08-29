terraform {
  backend "s3" {
    bucket         = "confluxdb-prod-tfstate"
    key            = "production/confluxdb/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "aws_dynamodb_table.tflock.confluxdb"
    encrypt        = true
  }
}