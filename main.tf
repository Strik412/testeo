terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Obtener la VPC por defecto
data "aws_vpc" "default" {
  default = true
}

# Obtener las subnets por defecto (excluyendo us-east-1e)
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  
  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
  }
}

# AMI más reciente de Amazon Linux 2
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Security Group para ALB
resource "aws_security_group" "alb" {
  name        = "terraform-alb-sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-alb-sg"
  }
}

# Security Group para instancias EC2
resource "aws_security_group" "instances" {
  name        = "terraform-instances-sg"
  description = "Allow traffic from ALB and SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # ⚠️ Abierto para GitHub Actions
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-instances-sg"
  }
}

# Data source para obtener rol IAM existente (para labs de AWS)
# Comentado porque en labs no tenemos permisos IAM
# data "aws_iam_role" "existing_role" {
#   name = "voclabs"
# }

# Instance Profile - Opcional, sin rol IAM
# resource "aws_iam_instance_profile" "ec2_profile" {
#   name = "terraform-ec2-profile"
#   role = data.aws_iam_role.existing_role.name
# }

# Application Load Balancer
resource "aws_lb" "app" {
  name               = "terraform-asg"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids

  tags = {
    Name = "terraform-asg"
  }
}

# Target Group
resource "aws_lb_target_group" "instances" {
  name     = "terraform-asg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    interval            = 30
    path                = "/health.html"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.instances.arn
  }
}

# Key Pair para SSH - Genera localmente
resource "tls_private_key" "deployer" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Guardar la private key localmente (sensible)
resource "local_sensitive_file" "private_key" {
  filename = "${path.module}/deployer_key.pem"
  content  = tls_private_key.deployer.private_key_pem
}

resource "aws_key_pair" "deployer" {
  key_name   = "terraform-deployer-key"
  public_key = tls_private_key.deployer.public_key_openssh
}

# Launch Template
resource "aws_launch_template" "app" {
  name_prefix   = "terraform-asg-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.deployer.key_name

  vpc_security_group_ids = [aws_security_group.instances.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = false
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              set -e
              yum update -y
              yum install -y docker git
              amazon-linux-extras install -y nginx1

              # Enable services
              systemctl enable --now docker
              systemctl enable --now nginx

              # Simple health endpoint so ALB health checks pass before deploy
              echo "ok" > /usr/share/nginx/html/health.html
              echo "<h1>Placeholder - awaiting GitHub Actions deployment</h1>" > /usr/share/nginx/html/index.html

              # Docker group for ec2-user
              usermod -a -G docker ec2-user
              
              # Crear directorio para la aplicación
              mkdir -p /home/ec2-user/app
              chown ec2-user:ec2-user /home/ec2-user/app
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "terraform-asg-instance"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app" {
  name                    = "terraform-asg"
  min_size                = 2
  max_size                = 7
  desired_capacity        = 2
  vpc_zone_identifier     = data.aws_subnets.default.ids
  target_group_arns       = [aws_lb_target_group.instances.arn]
  health_check_type       = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Asignar IP pública automáticamente
  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "terraform-asg-instance"
    propagate_at_launch = true
  }
}

# Auto Scaling Policy - CPU (70% threshold)
resource "aws_autoscaling_policy" "cpu_scaling" {
  name                   = "terraform-asg-cpu-policy"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.app.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# Auto Scaling Policy - Memory/Network (high threshold to avoid initial scaling)
resource "aws_autoscaling_policy" "memory_scaling" {
  name                   = "terraform-asg-memory-policy"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.app.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageNetworkIn"
    }
    target_value = 10000000.0  # 10 MB/s - high threshold
  }
}

# Data source para obtener las instancias del ASG
data "aws_instances" "asg_instances" {
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.app.name]
  }
  depends_on = [aws_autoscaling_group.app]
}

# Output
output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.app.dns_name
}

output "instance_ids" {
  description = "IDs of the EC2 instances in the ASG"
  value       = data.aws_instances.asg_instances.ids
  depends_on  = [aws_autoscaling_group.app]
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

output "instance_ips" {
  description = "Public IPs of EC2 instances for SSH access"
  value       = data.aws_instances.asg_instances.public_ips
  depends_on  = [aws_autoscaling_group.app]
}

output "private_key" {
  description = "Private key for SSH access"
  value       = tls_private_key.deployer.private_key_pem
  sensitive   = true
}
