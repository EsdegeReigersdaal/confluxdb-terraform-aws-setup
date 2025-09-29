ConfluxDB on AWS (Terraform)
=================================

Infrastructure-as-Code for the ConfluxDB data platform on AWS. It provisions a secure, private-by-default environment with:

- ECS Fargate cluster hosting a Dagster Hybrid agent in private subnets
- Ephemeral worker task definition for Dagster/Meltano/SQLMesh jobs
- RDS PostgreSQL (private subnets, managed master user secret)
- VPC with NAT and VPC Endpoints (ECR, ECS, Logs, Secrets Manager)
- Security groups with least-privilege rules
- ECR repositories for agent and worker images
- IAM roles for execution, agent control, and worker data access

Prerequisites
-------------
- Terraform 1.13+
- AWS provider ~> 6.12
- AWS credentials with access to the target account
- S3 bucket for backend state (configured in `backend.tf`)

Repository Layout
-----------------
- `vpc.tf`: VPC, subnets, NAT, flow logs
- `security-groups.tf`: SG for app tasks and RDS, VPC endpoint SG
- `endpoints.tf`: Interface/Gateway endpoints for private AWS access
- `database.tf`: RDS PostgreSQL in private subnets, managed password
- `ecr.tf`: ECR repositories for agent and worker images
- `ecs.tf`: ECS cluster, Dagster agent service, worker task definition
- `iam.tf`: IAM OIDC (GitHub), ECS execution role, agent/worker roles
- `secrets.tf`: Secrets Manager secrets (managed by Terraform)
- `variables.tf`: Configuration knobs (CPU/memory, images, secrets)
- `environments/sample.tfvars`: Example settings to copy/tune

Quick Start
-----------
1) Initialize and validate

    terraform init -upgrade
    terraform validate

2) Configure variables

    cp environments/sample.tfvars environments/prod.tfvars
    # Edit environments/prod.tfvars to set:
    # - DAGSTER_CLOUD_URL
    # - image tags (dagster agent and worker)
    # - managed secrets to create (or leave empty)

3) Plan and apply

    terraform plan -var-file=environments/prod.tfvars -out=tfplan
    terraform apply tfplan

4) Secrets

   Terraform provisions the secrets required by the platform. After apply:

   - `prod/confluxdb/connection` (environment-specific) already contains the proxy endpoint, database name, username, password, and port consumed by the code worker via `require_postgres_credentials()`. No manual action required.
   - If `create_dagster_agent_token_secret` is true and you did not supply `var.dagster_agent_token_value`, populate the agent token secret:

        aws secretsmanager put-secret-value \
          --secret-id confluxdb/prod/dagster_agent_token \
          --secret-string "<DAGSTER_CLOUD_AGENT_TOKEN>"

   - Entries declared in `agent_managed_secrets` or `worker_managed_secrets` are created empty so you can set them after apply:

        aws secretsmanager put-secret-value \
          --secret-id confluxdb/prod/worker/MELTANO_API_KEY \
          --secret-string "<meltano_api_key>"

Images
------
- Agent image: push to `module.ecr_dagster.repository_url` with tag `var.dagster_agent_image_tag`
- Worker image: push to `module.ecr_confluxdb_code.repository_url` with tag `var.confluxdb_code_image_tag`

Secrets Management
------------------
Terraform keeps the runtime credentials in Secrets Manager:

- `prod/confluxdb/connection` - auto-populated Postgres connection secret consumed by the Dagster code worker and other integrations through the RDS proxy.
- `confluxdb/<env>/dagster_agent_token` - optional secret for the Dagster Cloud agent token (populate if you do not pass `var.dagster_agent_token_value`).
- `confluxdb/<env>/agent/<NAME>` and `confluxdb/<env>/worker/<NAME>` - placeholders created from `agent_managed_secrets` and `worker_managed_secrets`; set the values post-apply when needed.

You can still reference existing secrets via `dagster_agent_secrets`. Worker tasks now fetch credentials at runtime; nothing is injected via the ECS task definition.


Security Model
--------------
- App security group is applied to agent and worker tasks; DB SG only allows ingress from the app SG on port 5432.
- ECS task execution role (pulls images, logs, reads secrets) is distinct from the task role used by your code.
- Dagster agent task role has permission to `ecs:RunTask` and `iam:PassRole` for the worker/execution roles.
- The RDS proxy IAM role has `secretsmanager:GetSecretValue` access to the master user secret so database sessions can authenticate.

Key Variables (excerpt)
-----------------------
- `dagster_agent_cpu`, `dagster_agent_memory`, `dagster_agent_desired_count`
- `confluxdb_code_image_tag`, `worker_cpu`, `worker_memory`
- `dagster_agent_env`, `dagster_agent_secrets`
- `agent_managed_secrets`, `worker_managed_secrets`
- `worker_task_role_policy_arns`

Outputs
-------
- `ecs_cluster_name`: ECS cluster name
- `ecs_dagster_agent_service_name`: Agent service name
- `ecs_worker_task_definition_arn`: Worker task definition ARN
- `rds_master_user_secret_arn`: RDS master user secret ARN
- `app_security_group_id`: App SG ID
- `dagster_agent_token_secret_arn`: Agent token secret ARN (if created)

Troubleshooting
---------------
- Ensure AWS credentials are configured; `terraform plan` contacts AWS for data sources.
- If using the S3 backend, verify the bucket/key/region exist; add DynamoDB locking if needed.
- VPC endpoints for ECS/ECR/Logs/Secrets must be created for private networking to work.

CI/CD Inputs (GitHub)
---------------------
Provide these via GitHub Repository Variables and Secrets. The workflow composes a `runtime.auto.tfvars.json` from them at run time, so you don’t commit tfvars.

Variables (non-sensitive)

| Name | Type | Example | Description |
| ---- | ---- | ------- | ----------- |
| `IAM_ROLE_ARN` | string | `arn:aws:iam::123456789012:role/confluxdb-prod-GithubActionsRole` | OIDC role assumed by the workflow |
| `DAGSTER_CLOUD_URL_PROD` | string | `https://esdege-reigersdaal.dagster.plus/prod` | Dagster Cloud URL (prod) |
| `DAGSTER_CLOUD_URL_DEV` | string | `https://esdege-reigersdaal.dagster.plus/dev` | Dagster Cloud URL (dev) |
| `DAGSTER_AGENT_IMAGE_TAG` | string | `v1.0.0` | Tag for Dagster agent image |
| `CONFLUXDB_CODE_IMAGE_TAG` | string | `v1.0.0` | Tag for ConfluxDB worker image |
| `AGENT_MANAGED_SECRETS_JSON` | JSON object | `{}` | Map of agent secret names to metadata (values set post-apply) |
| `WORKER_MANAGED_SECRETS_JSON` | JSON object | `{}` | Map of worker secret names to metadata (values set post-apply) |
| `WORKER_TASK_ROLE_POLICY_ARNS_JSON` | JSON array | `[]` | List of managed policy ARNs to attach to worker task role |

Secrets (sensitive)

| Name | Example | Description |
| ---- | ------- | ----------- |
| `DAGSTER_AGENT_TOKEN` | `dagster1-...` | Agent token written to Secrets Manager post-apply |

JSON payload examples

Worker managed secrets to create (values set post-apply via AWS CLI; retrieved at runtime by the workloads):

```
WORKER_MANAGED_SECRETS_JSON = {
  "MELTANO_API_KEY": {},
  "SQLMESH_API_KEY": {}
}
```

Attach policies to worker task role (least privilege recommended):

```
WORKER_TASK_ROLE_POLICY_ARNS_JSON = [
  "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
]
```

License
-------
Proprietary. All rights reserved unless stated otherwise by the repository owner.
