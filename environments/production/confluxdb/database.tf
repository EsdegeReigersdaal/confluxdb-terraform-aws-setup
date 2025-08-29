# environments/production/confluxdb/database.tf

# 1. Create a DB Subnet Group
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "confluxdb-db-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "ConfluxDB DB Subnet Group"
  }
}

# 2. Create the PostgreSQL RDS Instance
resource "aws_db_instance" "postgres_db" {
  identifier           = "confluxdb-postgres-db"
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "postgres"
  engine_version       = "17.5"
  # db.t4g.micro is a burstable, ARM-based instance, often the cheapest option.
  instance_class       = "db.t4g.micro"
  db_name              = "confluxdb"
  username             = jsondecode(aws_secretsmanager_secret_version.db_credentials_version.secret_string)["username"]
  password             = jsondecode(aws_secretsmanager_secret_version.db_credentials_version.secret_string)["password"]
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  # Best Practices
  multi_az               = false
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false

  tags = {
    Name = "confluxdb-postgres-db"
  }
}