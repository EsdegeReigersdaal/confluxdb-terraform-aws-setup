# Remote state configuration stored in S3.
# Stores Terraform state in S3 and enables locking for safe collaboration.

terraform {
  backend "s3" {
    bucket       = "confluxdb-prod-tfstate-228407934486-eu-west-1"
    key          = "confluxdb/terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = "true"
  }
}
