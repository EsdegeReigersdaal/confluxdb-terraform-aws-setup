# -----------------------------------------------------------------------------
# VPC Endpoints for private ECS/ECR/Logs/Secrets access
# -----------------------------------------------------------------------------
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
    },

    ecr_api = {
      service             = "ecr.api"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [module.vpc_endpoint_sg.security_group_id]
      private_dns_enabled = true
      tags                = { Name = "${local.project_name}-ecr-api-vpc-endpoint" }
    },

    ecr_dkr = {
      service             = "ecr.dkr"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [module.vpc_endpoint_sg.security_group_id]
      private_dns_enabled = true
      tags                = { Name = "${local.project_name}-ecr-dkr-vpc-endpoint" }
    },

    ecs = {
      service             = "ecs"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [module.vpc_endpoint_sg.security_group_id]
      private_dns_enabled = true
      tags                = { Name = "${local.project_name}-ecs-vpc-endpoint" }
    },

    secrets_manager = {
      service             = "secretsmanager"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [module.vpc_endpoint_sg.security_group_id]
      private_dns_enabled = true
      tags                = { Name = "${local.project_name}-secretsmanager-vpc-endpoint" }
    },

    logs = {
      service             = "logs"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [module.vpc_endpoint_sg.security_group_id]
      private_dns_enabled = true
      tags                = { Name = "${local.project_name}-logs-vpc-endpoint" }
    }
  }

  tags = {
    Project = local.project_name
  }

}
