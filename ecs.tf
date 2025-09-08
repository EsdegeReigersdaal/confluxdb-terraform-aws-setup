module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 9.0"

  cluster_name = "${local.project_name}-${local.environment}-cluster"

  create_cloudwatch_log_group = true
  cloudwatch_log_group_name   = "/ecs/${local.project_name}-${local.environment}"

  create_iam_roles = true
  task_role_policy_arns = [aws_iam_policy.read_rds_secret.arn]

  # ##############################################################################
  # SERVICE DEFINITION (Dagster UI)
  # ##############################################################################
  services = {
    dagster-ui = {
      # Task Definition
      cpu    = 256
      memory = 512

      container_definitions = {
        dagster-webserver = {
          essential = true
          image     = "${module.ecr.repositories["dagster"].repository_url}:latest"
          port_mappings = [{
            container_port = 3000
            host_port      = 3000
          }]

          secrets = [
            { name = "DB_USERNAME", valueFrom = "${module.rds.master_user_secret.arn}:username::" },
            { name = "DB_PASSWORD", valueFrom = "${module.rds.master_user_secret.arn}:password::" },
            { name = "DB_HOST", valueFrom = "${module.rds.master_user_secret.arn}:host::" },
            { name = "DB_PORT", valueFrom = "${module.rds.master_user_secret.arn}:port::" },
            { name = "DB_NAME", valueFrom = "${module.rds.master_user_secret.arn}:dbname::" },
          ]
        }
      }

      desired_count = 1
      subnet_ids    = module.vpc.private_subnets
      security_group_ids = [module.app_sg.security_group_id]

      load_balancer = {
        create_alb      = true
        vpc_id          = module.vpc.vpc_id
        alb_name        = "${local.project_name}-${local.environment}-alb"
        alb_subnet_ids  = module.vpc.public_subnets
        alb_security_group_ids = [module.lb_sg.security_group_id]

        # Target Group settings
        target_group = {
          port     = 3000
          protocol = "HTTP"
          health_check = {
            path                = "/dagit_info"
            protocol            = "HTTP"
            matcher             = "200"
            interval            = 30
            timeout             = 5
            healthy_threshold   = 2
            unhealthy_threshold = 2
          }
        }

        # Listener settings
        listener = {
          port     = 80
          protocol = "HTTP"
        }
      }
    }
  }

  tags = {
    Project     = local.project_name
    Environment = local.environment
  }
}