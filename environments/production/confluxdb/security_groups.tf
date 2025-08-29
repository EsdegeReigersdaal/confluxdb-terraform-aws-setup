# environments/production/confluxdb/security_groups.tf

# 1. Security Group for all Fargate tasks (Runner and Agent)
resource "aws_security_group" "fargate_sg" {
  name        = "confluxdb-fargate-sg"
  description = "Allow outbound traffic for all Fargate tasks"
  vpc_id      = module.vpc.vpc_id

  # Allow all outbound traffic for connecting to GitHub, Dagster+, etc.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "confluxdb-fargate-sg"
  }
}

# 2. Security Group for the RDS PostgreSQL database
resource "aws_security_group" "rds_sg" {
  name        = "confluxdb-rds-sg"
  description = "Allow inbound traffic from Fargate tasks to the database"
  vpc_id      = module.vpc.vpc_id

  # UPDATED: Allow inbound traffic ONLY from the new Fargate security group.
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.fargate_sg.id]
  }

  tags = {
    Name = "confluxdb-rds-sg"
  }
}