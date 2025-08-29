# environments/production/confluxdb/endpoints.tf

# 1. S3 Gateway Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id          = module.vpc.vpc_id
  service_name    = "com.amazonaws.${var.aws_region}.s3"
  route_table_ids = module.vpc.private_route_table_ids

  tags = {
    Name = "confluxdb-s3-gateway-endpoint"
  }
}

# 2. Interface Endpoints for other AWS Services
resource "aws_vpc_endpoint" "interface_endpoints" {
  for_each = toset([
    "secretsmanager",
    "ecr.api",
    "ecr.dkr",
    "logs"
  ])

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = module.vpc.private_subnets

  security_group_ids  = [aws_security_group.fargate_sg.id]

  tags = {
    Name = "confluxdb-${each.key}-interface-endpoint"
  }
}