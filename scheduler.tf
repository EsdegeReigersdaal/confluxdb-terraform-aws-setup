# -----------------------------------------------------------------------------
# ECS Service off-hours scheduler (UTC)
# Scales Dagster agent service to 0 between 18:00–06:00 UTC daily
# -----------------------------------------------------------------------------

locals {
  ecs_service_resource_id = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.dagster_agent.name}"
}

resource "aws_appautoscaling_target" "dagster_service" {
  service_namespace  = "ecs"
  resource_id        = local.ecs_service_resource_id
  scalable_dimension = "ecs:service:DesiredCount"

  min_capacity = 0
  max_capacity = var.dagster_agent_desired_count

  depends_on = [aws_ecs_service.dagster_agent]
}

# Scale down to 0 at 18:00 UTC daily
resource "aws_appautoscaling_scheduled_action" "dagster_off_hours_down" {
  name               = "${local.project_name}-${local.environment}-dagster-offhours-down"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.dagster_service.resource_id
  scalable_dimension = aws_appautoscaling_target.dagster_service.scalable_dimension
  schedule           = "cron(0 18 * * ? *)"

  scalable_target_action {
    min_capacity = 0
    max_capacity = 0
  }
}

# Scale up to configured count at 06:00 UTC daily
resource "aws_appautoscaling_scheduled_action" "dagster_off_hours_up" {
  name               = "${local.project_name}-${local.environment}-dagster-offhours-up"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.dagster_service.resource_id
  scalable_dimension = aws_appautoscaling_target.dagster_service.scalable_dimension
  schedule           = "cron(0 6 * * ? *)"

  scalable_target_action {
    min_capacity = var.dagster_agent_desired_count
    max_capacity = var.dagster_agent_desired_count
  }
}

