# Secrets Manager resources.
# Provisions Secrets Manager entries for the Dagster agent token and other runtime credentials.

# Creates the optional Dagster Cloud agent token secret.
resource "aws_secretsmanager_secret" "dagster_agent_token" {
  count = var.create_dagster_agent_token_secret ? 1 : 0

  name        = "${local.project_name}/${local.environment}/dagster_agent_token"
  description = "Dagster Cloud agent token for ${local.project_name}-${local.environment}"

  tags = {
    Name        = "${local.project_name}-${local.environment}-dagster-agent-token"
    Project     = local.project_name
    Environment = local.environment
  }
}

# Stores the provided agent token value when supplied.
resource "aws_secretsmanager_secret_version" "dagster_agent_token" {
  count = var.create_dagster_agent_token_secret && var.dagster_agent_token_value != null ? 1 : 0

  secret_id     = aws_secretsmanager_secret.dagster_agent_token[0].id
  secret_string = var.dagster_agent_token_value
}

# Creates agent-specific secrets defined in Terraform variables.
resource "aws_secretsmanager_secret" "agent_managed" {
  for_each = var.agent_managed_secrets

  name        = "${local.project_name}/${local.environment}/agent/${each.key}"
  description = coalesce(each.value.description, "Agent secret for ${each.key}")

  tags = {
    Name        = "${local.project_name}-${local.environment}-agent-${each.key}"
    Project     = local.project_name
    Environment = local.environment
  }
}

# Seeds agent managed secrets with initial values when provided.
resource "aws_secretsmanager_secret_version" "agent_managed" {
  for_each = { for k, v in var.agent_managed_secrets : k => v if try(v.value, null) != null }

  secret_id     = aws_secretsmanager_secret.agent_managed[each.key].id
  secret_string = each.value.value
}

# Creates worker secrets requested in configuration.
resource "aws_secretsmanager_secret" "worker_managed" {
  for_each = var.worker_managed_secrets

  name        = "${local.project_name}/${local.environment}/worker/${each.key}"
  description = coalesce(each.value.description, "Worker secret for ${each.key}")

  tags = {
    Name        = "${local.project_name}-${local.environment}-worker-${each.key}"
    Project     = local.project_name
    Environment = local.environment
  }
}

# Writes initial payloads to worker secrets when provided.
resource "aws_secretsmanager_secret_version" "worker_managed" {
  for_each = { for k, v in var.worker_managed_secrets : k => v if try(v.value, null) != null }

  secret_id     = aws_secretsmanager_secret.worker_managed[each.key].id
  secret_string = each.value.value
}
