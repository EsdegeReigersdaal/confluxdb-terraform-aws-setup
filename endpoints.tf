# VPC endpoints for private service access.
# Provides private connectivity to AWS services required by the ECS platform.

# Configures the S3 gateway endpoint and optional interface endpoints for private access.
module "endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.0.1"

  vpc_id = module.vpc.vpc_id
  security_group_ids = [
    module.vpc_endpoint_sg.security_group_id
  ]

  endpoints = {
    s3 = {
      service_type    = "Gateway"
      service         = "s3"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = "${local.project_name}-s3-vpc-endpoint" }
    }
  }

  tags = {
    Project = local.project_name
  }

}
