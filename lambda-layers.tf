# Lambda layer packaging for shared dependencies.
# Provides pg8000 and related libraries to the data API Lambda via a managed layer.

data "archive_file" "db_api_layer" {
  type        = "zip"
  source_dir  = "${path.module}/layers/db_api"
  output_path = "${path.module}/build/db-api-layer.zip"
}

resource "aws_lambda_layer_version" "db_api_deps" {
  layer_name          = "${local.project_name}-${local.environment}-db-api-deps"
  description         = "Shared dependencies for the ConfluxDB data API Lambda"
  compatible_runtimes = ["python3.12"]
  filename            = data.archive_file.db_api_layer.output_path
  source_code_hash    = data.archive_file.db_api_layer.output_base64sha256
}
