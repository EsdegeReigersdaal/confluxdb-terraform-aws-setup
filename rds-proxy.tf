# RDS Proxy resources.
# Adds a managed database proxy so Lambda and ECS can reuse pooled postgres connections.

# Trust policy allowing the RDS service to assume the proxy role for secret access.
data "aws_iam_policy_document" "rds_proxy_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "rds_proxy" {
  name               = "${local.project_name}-${local.environment}-rds-proxy-role"
  assume_role_policy = data.aws_iam_policy_document.rds_proxy_assume.json
  description        = "IAM role that lets RDS Proxy read database credentials"
}

resource "aws_db_proxy" "db" {
  name                   = "${local.project_name}-${local.environment}-db-proxy"
  debug_logging          = false
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [module.rds_proxy_sg.security_group_id]
  vpc_subnet_ids         = module.vpc.private_subnets

  auth {
    auth_scheme = "SECRETS"
    secret_arn  = module.rds.db_instance_master_user_secret_arn
    iam_auth    = "DISABLED"
  }

  tags = {
    Name = "${local.project_name}-${local.environment}-db-proxy"
  }
}

resource "aws_db_proxy_default_target_group" "db" {
  db_proxy_name = aws_db_proxy.db.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 75
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "db_instance" {
  db_instance_identifier = module.rds.db_instance_identifier
  db_proxy_name          = aws_db_proxy.db.name
  target_group_name      = aws_db_proxy_default_target_group.db.name
}
