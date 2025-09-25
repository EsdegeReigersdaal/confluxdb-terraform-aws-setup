# Input variables for this module.
# Centralizes tunable inputs for compute sizing, credentials, and automation integration.

# Configures the Dagster agent compute profile, image version, and environment overrides.

variable "dagster_agent_cpu" {
  description = "vCPU units for the Dagster agent task (valid Fargate value)"
  type        = number
  default     = 256
}

variable "dagster_agent_memory" {
  description = "Memory (MiB) for the Dagster agent task (valid Fargate value)"
  type        = number
  default     = 512
}

variable "dagster_agent_desired_count" {
  description = "Number of Dagster agent tasks to run"
  type        = number
  default     = 1
}

variable "dagster_agent_image_tag" {
  description = "Image tag for the Dagster agent ECR image"
  type        = string
  default     = "ef5bc6925d9e"
}


variable "dagster_agent_env" {
  description = "Environment variables for the Dagster agent container"
  type        = map(string)
  default     = {}
}

variable "dagster_agent_secrets" {
  description = "Secrets to inject into the Dagster agent container"
  type = list(object({
    name = string
    # Accepts the ARN for the secret or parameter injected into the container.
    value_from = string
  }))
  default = []
}

variable "dagster_agent_log_retention_days" {
  description = "CloudWatch log retention days for the Dagster agent"
  type        = number
  default     = 14
}

# Tunes worker task sizing, images, and secret injection.

variable "confluxdb_code_image_tag" {
  description = "Image tag for the ConfluxDB worker code image (Dagster+Meltano+SQLMesh)"
  type        = string
  default     = "latest"
}

variable "worker_cpu" {
  description = "vCPU units for worker tasks (valid Fargate value)"
  type        = number
  default     = 1024
}

variable "worker_memory" {
  description = "Memory (MiB) for worker tasks (valid Fargate value)"
  type        = number
  default     = 2048
}

variable "worker_env" {
  description = "Environment variables for the worker container"
  type        = map(string)
  default     = {}
}

variable "worker_secrets" {
  description = "Secrets to inject into the worker container"
  type = list(object({
    name = string
    # Accepts the ARN for the secret or parameter injected into the container.
    value_from = string
  }))
  default = []
}

variable "worker_log_retention_days" {
  description = "CloudWatch log retention days for worker tasks"
  type        = number
  default     = 14
}

# Allows optional IAM policies to be attached for worker data access.

variable "worker_task_role_policy_arns" {
  description = "List of managed policy ARNs to attach to the worker task role for data access (e.g., S3, Glue)"
  type        = list(string)
  default     = []
}

# Defines Terraform-managed secrets that are provisioned and wired into containers.
variable "agent_managed_secrets" {
  description = "Map of agent secret env var names to metadata and optional initial values. Stored at <project>/<env>/agent/<ENV_VAR_NAME>"
  type = map(object({
    description = optional(string)
    value       = optional(string)
  }))
  default = {}
}

variable "worker_managed_secrets" {
  description = "Map of worker secret env var names to metadata and optional initial values. Stored at <project>/<env>/worker/<ENV_VAR_NAME>"
  type = map(object({
    description = optional(string)
    value       = optional(string)
  }))
  default = {}
}

# Controls creation and population of the Dagster agent token secret.

variable "create_dagster_agent_token_secret" {
  description = "Create a Secrets Manager secret for the Dagster Cloud agent token and wire it into the agent container"
  type        = bool
  default     = true
}

variable "dagster_agent_token_value" {
  description = "Dagster Cloud agent token value. If set, a secret version will be written (note: value will be stored in TF state). Prefer setting via CI/CD post-apply if possible."
  type        = string
  default     = null
  sensitive   = true
}
# Establishes global AWS region and environment naming defaults.

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment (e.g., dev, prod)"
  type        = string
  default     = "prod"
}

# Targets the correct Dagster Cloud organization, deployment, and URL.

variable "dagster_cloud_organization" {
  description = "Dagster Cloud organization slug (DAGSTER_CLOUD_ORGANIZATION)"
  type        = string
  default     = "esdege-reigersdaal"
}

variable "dagster_cloud_deployment" {
  description = "Dagster Cloud deployment name (DAGSTER_CLOUD_DEPLOYMENT)"
  type        = string
  default     = "confluxdb"
}

variable "dagster_cloud_url" {
  description = "Dagster Cloud control plane URL (set to https://eu.dagster.cloud for EU)"
  type        = string
  default     = "https://esdege-reigersdaal.dagster.plus"
}

variable "dagster_cloud_branch_deployments" {
  description = "Whether the agent should serve branch deployments (true/false)"
  type        = bool
  default     = false
}

# Identifies the GitHub repositories allowed to assume CI roles.

variable "github_agent_repo" {
  description = "GitHub repository NAME (without org) for the Dagster agent image CI (e.g., 'dagster-agent')."
  type        = string
  default     = "confluxdb-dagster-agent"
}

variable "github_worker_repo" {
  description = "GitHub repository NAME (without org) for the worker code image CI (e.g., 'confluxdb-code')."
  type        = string
  default     = "confluxdb"
}

variable "github_ci_branch" {
  description = "Branch name in the app repos allowed to assume their CI roles (e.g., 'main')."
  type        = string
  default     = "main"
}

# Enables or disables optional infrastructure features.

variable "enable_vpc_endpoints" {
  description = "Enable interface VPC endpoints (ECR API/DKR, ECS, Secrets Manager). S3 Gateway endpoint remains enabled regardless."
  type        = bool
  default     = false
}
variable "db_api_allowed_source_ips" {
  description = "List of IPv4 addresses allowed to invoke the data API. Set via TF_VAR_db_api_allowed_source_ips (e.g., in a GitHub environment variable)."
  type        = list(string)
  default     = []
}

variable "db_api_resource_prefix" {
  description = "Base schema/table path required in the data API resource header (e.g., public/diensten)."
  type        = string
  default     = "public/diensten"
}

variable "db_api_auth_key_value" {
  description = "Optional initial value for the data API authentication key. Supply via TF_VAR_db_api_auth_key_value (for example by mapping a GitHub environment secret)."
  type        = string
  default     = null
  sensitive   = true
}
