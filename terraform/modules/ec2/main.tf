# ==============================================================================
# Dedicated CI Runner / Bastion EC2 Instance (SSM Session Manager Managed)
# ==============================================================================

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security group: ZERO inbound rules needed! SSM works purely outbound over HTTPS 443
resource "aws_security_group" "runner" {
  name        = "${var.project_name}-${var.environment}-runner-sg"
  description = "Security group for CI Runner (Outbound only, managed via SSM)"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-runner-sg"
    Environment = var.environment
  }
}

resource "aws_instance" "runner" {
  ami                  = data.aws_ami.al2023.id
  instance_type        = var.instance_type
  subnet_id            = var.subnet_id
  vpc_security_group_ids = [aws_security_group.runner.id]
  iam_instance_profile = var.instance_profile_name

  # Security best practice: Strict IMDSv2
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y docker git
              systemctl enable --now docker
              usermod -aG docker ec2-user
              EOF

  tags = {
    Name        = "${var.project_name}-${var.environment}-runner"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
