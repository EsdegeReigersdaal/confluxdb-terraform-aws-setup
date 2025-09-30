# Relational database resources.
# Provisions the private PostgreSQL database and its supporting subnet group.

# Defines the database subnet group so RDS stays within the private subnets.
resource "aws_db_subnet_group" "rds" {
  name       = "${local.project_name}-${local.environment}-rds-sng"
  subnet_ids = module.vpc.database_subnets

  tags = {
    Name = "${local.project_name}-${local.environment}-rds-sng"
  }
}

# Manages the PostgreSQL instance with backups, monitoring, and IAM-integrated credentials.
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.12.0"

  identifier = "${local.project_name}-${local.environment}-rds"

  family                = "postgres17"
  engine                = "postgres"
  engine_version        = "17.5"
  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  storage_type          = "gp3"
  max_allocated_storage = 100

  db_name = "confluxdb"

  username = "confluxdb_postgresql"
  port     = 5432

  manage_master_user_password                       = true
  manage_master_user_password_rotation              = true
  master_user_password_rotate_immediately           = false
  master_user_password_rotation_schedule_expression = "rate(15 days)"

  iam_database_authentication_enabled = true

  vpc_security_group_ids = [module.rds_sg.security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.rds.name

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true

  multi_az                              = false
  deletion_protection                   = true
  skip_final_snapshot                   = false
  backup_retention_period               = 7
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  create_monitoring_role                = true
  monitoring_interval                   = 60
  monitoring_role_name                  = "${local.project_name}-${local.environment}-monitor-role"
  monitoring_role_use_name_prefix       = true
  monitoring_role_description           = "Monitoring role for database"

  parameters = [
    {
      name  = "autovacuum"
      value = 1
    },
    {
      name  = "client_encoding"
      value = "utf8"
    },
    {
      name  = "rds.force_ssl"
      value = 1
    }
  ]

  db_option_group_tags = {
    "Sensitive" = "low"
  }
  db_parameter_group_tags = {
    "Sensitive" = "low"
  }
  cloudwatch_log_group_tags = {
    "Sensitive" = "high"
  }

  tags = {
    Project     = local.project_name
    Environment = local.environment
  }
}
