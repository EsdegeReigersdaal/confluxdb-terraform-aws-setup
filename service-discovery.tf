# -----------------------------------------------------------------------------
# Cloud Map namespace for Dagster ECS code servers
# -----------------------------------------------------------------------------

resource "aws_service_discovery_private_dns_namespace" "dagster" {
  name        = "dagster-agent-${local.project_name}-${local.environment}.local"
  description = "Dagster agent service discovery namespace"
  vpc         = module.vpc.vpc_id
}

