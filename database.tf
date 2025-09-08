resource "aws_db_subnet_group" "rds" {
  name       = "${local.project_name}-${local.environment}-rds-sng"
  subnet_ids = module.vpc.database_subnets

  tags = {
    Name = "${local.project_name}-${local.environment}-rds-sng"
  }
}

# -----------------------------------------------------------------------------
# AWS RDS PostgreSQL Database
# Creates a secure, private database for the data platform.
# -----------------------------------------------------------------------------
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.12.0"

  identifier = "${local.project_name}-${local.environment}-rds"

  engine                = "postgres"
  engine_version        = "15.6"
  instance_class        = "db.t4g.small" # Graviton instance for better price/performance
  allocated_storage     = 20
  storage_type          = "gp3"
  max_allocated_storage = 100 # Allows storage to autoscale up to 100 GB

  db_name = "dataplatform" # The initial database to be created

  manage_master_user_password = true
  master_username             = "dagsteradmin"

  # Networking - Places the database in private subnets and attaches the correct security group.
  publicly_accessible    = false
  vpc_security_group_ids = [module.rds_sg.security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.rds.name

  # ##############################################################################
  # PRODUCTION-SPECIFIC SETTINGS (Defaults are for dev/test)
  # ##############################################################################

  # For true production, set multi_az = true for high availability.
  multi_az = false

  # For production, set a deletion_protection = true and skip_final_snapshot = false
  deletion_protection     = true
  skip_final_snapshot     = false
  backup_retention_period = 7

  performance_insights_enabled = true

  tags = {
    Project     = local.project_name
    Environment = local.environment
  }
}