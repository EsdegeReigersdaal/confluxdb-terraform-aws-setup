terraform {
  backend "s3" {
    bucket       = "confluxdb-prod-tfstate-228407934486-eu-west-1"
    key          = "terraform-backend-setup/confluxdb.tfstate"
    region       = "eu-west-1"
    use_lockfile = "true"
  }
}