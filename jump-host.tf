# SSM-managed EC2 jump host for occasional database access.

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "jump_host" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc.private_subnets[0]
  vpc_security_group_ids      = [module.jump_sg.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.jump_host.name
  associate_public_ip_address = false
  monitoring                  = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = <<-EOF
#!/bin/bash
set -euxo pipefail
dnf install -y postgresql15 jq
EOF

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
  }

  tags = {
    Name        = "${local.project_name}-${local.environment}-jump"
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
  }
}
