# Service discovery configuration.
# Creates a Cloud Map namespace so the agent can discover worker services.

resource "aws_service_discovery_private_dns_namespace" "dagster" {
  name        = "dagster-agent-${local.project_name}-${local.environment}.local"
  description = "Dagster agent service discovery namespace"
  vpc         = module.vpc.vpc_id
}

