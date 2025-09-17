# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
module "vpc_endpoint_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"

  name        = "${local.project_name}-${local.environment}-vpc-endpoint-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Allow HTTPS traffic to VPC endpoints"
      cidr_blocks = local.vpc_cidr
    },
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all outbound traffic"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

}

module "app_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"

  name        = "${local.project_name}-${local.environment}-confluxdb-sg"
  description = "Security group for the Fargate agent and run workers"
  vpc_id      = module.vpc.vpc_id

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}

resource "aws_security_group_rule" "app_sg_allow_internal_code_server" {
  description              = "Allow Dagster agent to reach worker code servers on gRPC port"
  type                     = "ingress"
  from_port                = 4000
  to_port                  = 4000
  protocol                 = "tcp"
  security_group_id        = module.app_sg.security_group_id
  source_security_group_id = module.app_sg.security_group_id
}

# -----------------------------------------------------------------------------
# Security Group for the RDS Database (This remains the same)
# Allows traffic only from the application's security group on the PostgreSQL port.
# -----------------------------------------------------------------------------
module "rds_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"

  name        = "${local.project_name}-${local.environment}-rds-sg"
  description = "Security group for the RDS database"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      description              = "Allow traffic from the Fargate application"
      source_security_group_id = module.app_sg.security_group_id
    },
  ]

  tags = {
    Name = "${local.project_name}-${local.environment}-rds-sg"
  }
}

