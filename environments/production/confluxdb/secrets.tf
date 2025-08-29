resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "confluxdb/production/db-credentials"
  tags = {
    Project = "ConfluxDB Data Platform"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id     = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
  })
}

# 5. Secret for the Dagster+ Agent Token
resource "aws_secretsmanager_secret" "dagster_agent_token" {
  name = "confluxdb/production/dagster-agent-token"
}

resource "aws_secretsmanager_secret_version" "dagster_agent_token_version" {
  secret_id     = aws_secretsmanager_secret.dagster_agent_token.id
  secret_string = var.dagster_agent_token
}