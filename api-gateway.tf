locals {
  db_api_allowed_source_ips   = [for ip in var.db_api_allowed_source_ips : trimspace(ip) if trimspace(ip) != ""]
  db_api_allowed_source_cidrs = [for ip in local.db_api_allowed_source_ips : strcontains(ip, "/") ? ip : "${ip}/32"]
}

# Data API exposure.
# Creates a Lambda-backed HTTP API that runs inside the private subnets and
# uses Secrets Manager credentials to reach the PostgreSQL RDS instance via the proxy.

data "archive_file" "db_api_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/db_api"
  output_path = "${path.module}/build/db-api-lambda.zip"
}

# Trust policy that lets Lambda assume its execution role.
data "aws_iam_policy_document" "db_api_lambda_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# Inline policy granting log emission and Secrets Manager access for DB credentials.
data "aws_iam_policy_document" "db_api_lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${local.aws_region}:${data.aws_caller_identity.current.account_id}:*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [module.rds.db_instance_master_user_secret_arn, aws_secretsmanager_secret.db_api_auth.arn]
  }
}

resource "aws_iam_role" "db_api_lambda" {
  name               = "${local.project_name}-${local.environment}-db-api-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.db_api_lambda_assume.json
}

resource "aws_iam_role_policy" "db_api_lambda" {
  name   = "${local.project_name}-${local.environment}-db-api-inline-policy"
  role   = aws_iam_role.db_api_lambda.id
  policy = data.aws_iam_policy_document.db_api_lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "db_api_lambda_basic" {
  role       = aws_iam_role.db_api_lambda.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "db_api_lambda_vpc" {
  role       = aws_iam_role.db_api_lambda.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_cloudwatch_log_group" "db_api_lambda" {
  name              = "/aws/lambda/${local.project_name}-${local.environment}-db-api"
  retention_in_days = 14
}

resource "aws_lambda_function" "db_api" {
  function_name = "${local.project_name}-${local.environment}-db-api"
  description   = "Lambda handler for the ConfluxDB data API"
  role          = aws_iam_role.db_api_lambda.arn
  runtime       = "python3.12"
  handler       = "handler.handler"

  filename         = data.archive_file.db_api_lambda.output_path
  source_code_hash = data.archive_file.db_api_lambda.output_base64sha256

  timeout     = 10
  memory_size = 256
  layers      = [aws_lambda_layer_version.db_api_deps.arn]

  environment {
    variables = {
      DB_SECRET_ARN      = module.rds.db_instance_master_user_secret_arn
      DB_HOST            = aws_db_proxy.db.endpoint
      DB_NAME            = module.rds.db_instance_name
      DB_PORT            = tostring(module.rds.db_instance_port)
      API_KEY_SECRET_ARN = aws_secretsmanager_secret.db_api_auth.arn
      ALLOWED_SOURCE_IPS = join(",", var.db_api_allowed_source_ips)
      RESOURCE_PREFIX    = var.db_api_resource_prefix
    }
  }

  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [module.api_lambda_sg.security_group_id]
  }

  depends_on = [aws_cloudwatch_log_group.db_api_lambda]
}

resource "aws_apigatewayv2_api" "db" {
  name          = "${local.project_name}-${local.environment}-db-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "db_lambda" {
  api_id                 = aws_apigatewayv2_api.db.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.db_api.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000
}

resource "aws_apigatewayv2_route" "db_proxy" {
  api_id    = aws_apigatewayv2_api.db.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.db_lambda.id}"
}

resource "aws_cloudwatch_log_group" "db_api_stage" {
  name              = "/aws/apigateway/${local.project_name}-${local.environment}-db-api"
  retention_in_days = 14
}

resource "aws_apigatewayv2_stage" "db" {
  api_id      = aws_apigatewayv2_api.db.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.db_api_stage.arn
    format = jsonencode({
      requestId         = "$context.requestId"
      ip                = "$context.identity.sourceIp"
      requestTime       = "$context.requestTime"
      httpMethod        = "$context.httpMethod"
      routeKey          = "$context.routeKey"
      status            = "$context.status"
      responseLength    = "$context.responseLength"
      integrationStatus = "$context.integrationStatus"
    })
  }
}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.db_api.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.db.execution_arn}/*/*"
}
