module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.0.1"

  name = "${local.project_name}-${local.environment}-vpc"
  cidr = local.vpc_cidr
  azs  = local.availability_zones

  private_subnets  = [for k, v in local.availability_zones : cidrsubnet(local.vpc_cidr, 8, k)]
  public_subnets   = [for k, v in local.availability_zones : cidrsubnet(local.vpc_cidr, 8, k + 4)]
  database_subnets = [for k, v in local.availability_zones : cidrsubnet(local.vpc_cidr, 8, k + 8)]

  private_subnet_names  = [for az in local.availability_zones : "private-${az}"]
  public_subnet_names   = [for az in local.availability_zones : "public-${az}"]
  database_subnet_names = [for az in local.availability_zones : "db-${az}"]

  create_database_subnet_group  = false
  manage_default_network_acl    = false
  manage_default_route_table    = false
  manage_default_security_group = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = true
  single_nat_gateway = true

  vpc_flow_log_iam_role_name            = "vpc-execution-role"
  vpc_flow_log_iam_role_use_name_prefix = false
  enable_flow_log                       = true
  create_flow_log_cloudwatch_log_group  = true
  create_flow_log_cloudwatch_iam_role   = true
  flow_log_max_aggregation_interval     = 60
}
