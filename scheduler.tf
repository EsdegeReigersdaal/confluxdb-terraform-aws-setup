# Off-hours scheduler automation.
# Automates stopping and starting the Dagster infrastructure with Lambda and EventBridge.

# Packages the scheduler Lambda code into a deployment ZIP.
data "archive_file" "offhours_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/scheduler"
  output_path = "${path.module}/build/scheduler-offhours.zip"
}

# Defines the trust policy that lets Lambda assume its execution role.
data "aws_iam_policy_document" "offhours_lambda_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# Grants the Lambda function logging privileges plus ECS scale and RDS start/stop permissions.
data "aws_iam_policy_document" "offhours_lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${local.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService"
    ]
    resources = [
      aws_ecs_service.dagster_agent.arn,
      format(
        "arn:aws:ecs:%s:%s:service/%s/*",
        local.aws_region,
        data.aws_caller_identity.current.account_id,
        aws_ecs_cluster.cluster.name,
      )
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["ecs:ListServices"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "rds:StartDBInstance",
      "rds:StopDBInstance",
      "rds:DescribeDBInstances"
    ]
    resources = [module.rds.db_instance_arn]
  }
}

# Provides the IAM role assumed by the scheduler Lambda function.
resource "aws_iam_role" "offhours_lambda" {
  name               = "${local.project_name}-${local.environment}-offhours-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.offhours_lambda_assume.json
}

# Attaches the permissions required for the scheduler automation.
resource "aws_iam_role_policy" "offhours_lambda" {
  name   = "${local.project_name}-${local.environment}-offhours-lambda-policy"
  role   = aws_iam_role.offhours_lambda.id
  policy = data.aws_iam_policy_document.offhours_lambda_policy.json
}

# Stores Lambda logs with a short retention window.
resource "aws_cloudwatch_log_group" "offhours_lambda" {
  name              = "/aws/lambda/${local.project_name}-${local.environment}-offhours"
  retention_in_days = 14
}

# Defines the Lambda function that orchestrates off-hours start and stop actions.
resource "aws_lambda_function" "offhours" {
  function_name = "${local.project_name}-${local.environment}-offhours-scheduler"
  description   = "Stops and starts Dagster infrastructure outside business hours"
  role          = aws_iam_role.offhours_lambda.arn
  runtime       = "python3.12"
  handler       = "handler.handler"

  filename         = data.archive_file.offhours_lambda.output_path
  source_code_hash = data.archive_file.offhours_lambda.output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER                    = aws_ecs_cluster.cluster.arn
      ECS_AGENT_SERVICE              = aws_ecs_service.dagster_agent.name
      ECS_AGENT_DESIRED_COUNT        = tostring(var.dagster_agent_desired_count)
      ECS_CODE_SERVICE_PREFIX        = "${local.project_name}-${local.environment}-"
      ECS_CODE_SERVICE_DESIRED_COUNT = "1"
      RDS_INSTANCE_ID                = module.rds.db_instance_identifier
    }
  }

  depends_on = [aws_cloudwatch_log_group.offhours_lambda]
}

# EventBridge rule that triggers the nightly shutdown.
resource "aws_cloudwatch_event_rule" "offhours_stop" {
  name                = "${local.project_name}-${local.environment}-offhours-stop"
  description         = "Stop Dagster platform outside working hours"
  schedule_expression = "cron(0 18 ? * MON-FRI *)"
}

# EventBridge rule that triggers the morning startup.
resource "aws_cloudwatch_event_rule" "offhours_start" {
  name                = "${local.project_name}-${local.environment}-offhours-start"
  description         = "Start Dagster platform each weekday morning"
  schedule_expression = "cron(0 6 ? * MON-FRI *)"
}

# Connects the stop schedule to the Lambda function.
resource "aws_cloudwatch_event_target" "offhours_stop" {
  rule      = aws_cloudwatch_event_rule.offhours_stop.name
  target_id = "offhours-stop"
  arn       = aws_lambda_function.offhours.arn
  input     = jsonencode({ action = "stop" })
}

# Connects the start schedule to the Lambda function.
resource "aws_cloudwatch_event_target" "offhours_start" {
  rule      = aws_cloudwatch_event_rule.offhours_start.name
  target_id = "offhours-start"
  arn       = aws_lambda_function.offhours.arn
  input     = jsonencode({ action = "start" })
}

# Grants EventBridge permission to invoke the stop action.
resource "aws_lambda_permission" "allow_events_stop" {
  statement_id  = "AllowExecutionFromCloudWatchStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.offhours.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.offhours_stop.arn
}

# Grants EventBridge permission to invoke the start action.
resource "aws_lambda_permission" "allow_events_start" {
  statement_id  = "AllowExecutionFromCloudWatchStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.offhours.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.offhours_start.arn
}
