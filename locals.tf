locals {
  aws_region               = "eu-west-1"
  environment              = "prod"
  project_name             = "confluxdb"
  component_name           = "confluxdb-infra"
  owner_name               = "Michael"
  cost_center_name         = "confluxdb-prod"
  availability_zones       = data.aws_availability_zones.available.names
  vpc_cidr           = "10.0.0.0/16"

}
