# Web Application Firewall configuration for the data API.
# Restricts API Gateway invocations to an allowlist of IP addresses at the edge layer.

resource "aws_wafv2_ip_set" "db_api_allowlist" {
  count              = length(local.db_api_allowed_source_cidrs) > 0 ? 1 : 0
  name               = "${local.project_name}-${local.environment}-db-api-ipset"
  description        = "Allowlisted source IPs for the ConfluxDB data API"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = local.db_api_allowed_source_cidrs
}

resource "aws_wafv2_web_acl" "db_api_allowlist" {
  count       = length(local.db_api_allowed_source_cidrs) > 0 ? 1 : 0
  name        = "${local.project_name}-${local.environment}-db-api-allowlist"
  description = "Blocks requests that are not in the approved IP list"
  scope       = "REGIONAL"

  default_action {
    block {}
  }

  rule {
    name     = "AllowKnownIps"
    priority = 1

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.db_api_allowlist[0].arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = replace("${local.project_name}${local.environment}DbApiAllow", "-", "")
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = replace("${local.project_name}${local.environment}DbApiWebAcl", "-", "")
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "db_api" {
  count        = length(local.db_api_allowed_source_cidrs) > 0 ? 1 : 0
  resource_arn = aws_apigatewayv2_stage.db.arn
  web_acl_arn  = aws_wafv2_web_acl.db_api_allowlist[0].arn
}
