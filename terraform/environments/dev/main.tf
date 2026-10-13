terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket       = "krumil-ecommerce-tfstate-311937350493-us-east-2"
    key          = "ecommerce/dev/terraform.tfstate"
    region       = "us-east-2"
    profile      = "aws-management"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  profile = "aws-management"
  region  = "us-east-2"
}

# S3 bucket for product images
resource "aws_s3_bucket" "product_images" {
  bucket = "krumil-ecommerce-images-311937350493-us-east-2"

  tags = {
    Name        = "ecommerce-product-images"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_versioning" "product_images" {
  bucket = aws_s3_bucket.product_images.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "product_images" {
  bucket = aws_s3_bucket.product_images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "product_images" {
  bucket = aws_s3_bucket.product_images.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "ecommerce-dev-vpc"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# Public subnets
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "ecommerce-public-a"
    Tier = "public"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true

  tags = {
    Name = "ecommerce-public-b"
    Tier = "public"
  }
}

# Private subnets
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name = "ecommerce-private-a"
    Tier = "private"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "us-east-2b"

  tags = {
    Name = "ecommerce-private-b"
    Tier = "private"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "ecommerce-dev-igw"
    Environment = "dev"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "ecommerce-public-rt"
    Environment = "dev"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "ecommerce-private-rt"
    Environment = "dev"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# ALB security group
resource "aws_security_group" "alb" {
  name        = "ecommerce-alb-sg"
  description = "Allow HTTP traffic to the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from internet"
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
    Name        = "ecommerce-alb-sg"
    Environment = "dev"
  }
}

# EC2 security group: only ALB can access app ports
resource "aws_security_group" "ec2" {
  name        = "ecommerce-ec2-sg"
  description = "Allow backend traffic only from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Backend traffic from ALB"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Frontend traffic from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = ["14.96.105.95/32"]
    prefix_list_ids = ["pl-03915406641cb1f53"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ecommerce-ec2-sg"
    Environment = "dev"
  }
}

# Application Load Balancer
resource "aws_lb" "app" {
  name               = "ecommerce-dev-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name        = "ecommerce-dev-alb"
    Environment = "dev"
  }
}

# Backend target group
resource "aws_lb_target_group" "app" {
  name        = "ecommerce-dev-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name        = "ecommerce-dev-tg"
    Environment = "dev"
  }
}

# Frontend target group
resource "aws_lb_target_group" "frontend" {
  name        = "ecommerce-dev-frontend-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name        = "ecommerce-dev-frontend-tg"
    Environment = "dev"
  }
}

# HTTP listener: API and uploads go to backend;
# all other paths go to frontend.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "backend_paths" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    path_pattern {
      values = ["/health", "/api/*", "/uploads/*"]
    }
  }
}

output "alb_dns_name" {
  description = "Public DNS name of the ecommerce ALB"
  value       = aws_lb.app.dns_name
}

output "alb_target_group_arn" {
  description = "Backend target group ARN"
  value       = aws_lb_target_group.app.arn
}

output "alb_frontend_target_group_arn" {
  description = "Frontend target group ARN"
  value       = aws_lb_target_group.frontend.arn
}

# EC2 launch template
resource "aws_launch_template" "app" {
  name          = "ecommerce-dev-lt"
  image_id      = "ami-09519cc56eb20524a"
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ecr_profile.name
  }

  vpc_security_group_ids = [
    aws_security_group.ec2.id
  ]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -eux
    apt-get update
    apt-get install -y docker.io
    systemctl enable --now docker
  EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name        = "ecommerce-dev-ec2"
      Environment = "dev"
      ManagedBy   = "Terraform"
    }
  }

  tags = {
    Name        = "ecommerce-dev-lt"
    Environment = "dev"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app" {
  name             = "ecommerce-dev-asg"
  min_size         = 1
  max_size         = 2
  desired_capacity = 1

  vpc_zone_identifier = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  target_group_arns = [
    aws_lb_target_group.app.arn,
    aws_lb_target_group.frontend.arn
  ]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 180

  tag {
    key                 = "Name"
    value               = "ecommerce-dev-asg-instance"
    propagate_at_launch = true
  }
}

# ECR repositories
resource "aws_ecr_repository" "backend" {
  name                 = "ecommerce-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "ecommerce-backend"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "ecommerce-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "ecommerce-frontend"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

output "backend_ecr_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "frontend_ecr_url" {
  value = aws_ecr_repository.frontend.repository_url
}

# EC2 IAM role
resource "aws_iam_role" "ec2_ecr_role" {
  name = "ecommerce-dev-ec2-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ecr_profile" {
  name = "ecommerce-dev-ec2-ecr-profile"
  role = aws_iam_role.ec2_ecr_role.name
}
