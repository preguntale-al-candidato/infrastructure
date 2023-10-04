### =====================================
### Elastic Container Registry Repository
### =====================================
resource "aws_ecr_repository" "backend" {
  name = "${local.name_prefix}-backend"

  force_delete = true # If true, will delete the repository even if it contains images. Defaults to false.

  image_scanning_configuration {
    scan_on_push = false
  }
}

data "aws_iam_policy_document" "backend_deployer_policy" {
  statement {
    sid    = "Permissions to deploy to the ECR repository"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        aws_iam_user.backend_deployer_user.arn
      ]
    }

    actions = [
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
  }
}

resource "aws_ecr_repository_policy" "backend_deployer_policy" {
  repository = aws_ecr_repository.backend.name
  policy     = data.aws_iam_policy_document.backend_deployer_policy.json
}

### =============
### Load Balancer
### =============
# Load Balancer security group
resource "aws_security_group" "lb_sg" {
  name        = "${local.name_prefix}-lb"
  description = "Allow HTTPS to ALB"
  vpc_id      = aws_vpc.main.id
}

# LB HTTPS Ingress rule
resource "aws_security_group_rule" "lb_https_ingress" {
  security_group_id = aws_security_group.lb_sg.id

  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

# LB Egress rule
resource "aws_security_group_rule" "lb_all_egress" {
  security_group_id = aws_security_group.lb_sg.id

  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

# Application Load Balancer
resource "aws_lb" "lb" {
  name               = local.name_prefix
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  enable_deletion_protection = false
}

# HTTPS ALB listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Default response not implemented"
      status_code  = "501"
    }
  }
}

# Route53 API record
resource "aws_route53_record" "api" {
  zone_id = module.route53.zone_id
  name    = "api"
  type    = "A"

  alias {
    name                   = aws_lb.lb.dns_name
    zone_id                = aws_lb.lb.zone_id
    evaluate_target_health = true
  }
}

# Target Group
resource "aws_lb_target_group" "backend" {
  name = "${local.name_prefix}-backend"

  protocol = "HTTP"
  port     = 8000
  vpc_id   = aws_vpc.main.id
}

# ALB listener rule
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    host_header {
      values = [aws_route53_record.api.fqdn]
    }
  }
}

### ==================
### Backend IAM config
### ==================
resource "aws_iam_role" "backend" {
  name = "${local.name_prefix}-backend"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "backend" {
  name = "${local.name_prefix}-backend"
  role = aws_iam_role.backend.name
}

data "aws_kms_alias" "ssm_default" {
  name = "alias/aws/ssm"
}

resource "aws_iam_role_policy" "backend" {
  name = "${local.name_prefix}-backend"
  role = aws_iam_role.backend.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["ecr:GetAuthorizationToken"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage"
        ]
        Resource = [aws_ecr_repository.backend.arn]
      },
      {
        Action   = ["ssm:GetParameter"],
        Effect   = "Allow",
        Resource = "arn:aws:ssm:us-east-1:301634789447:parameter/OPEN_AI_API_KEY"
      },
      {
        Action   = ["kms:Decrypt"],
        Effect   = "Allow",
        Resource = data.aws_kms_alias.ssm_default.target_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "transcriptions_backend_policy_attach" {
  role       = aws_iam_role.backend.name
  policy_arn = aws_iam_policy.transcriptions_uploader_policy.arn
}

resource "aws_iam_role_policy_attachment" "milvus_volume_policy_attach" {
  role       = aws_iam_role.backend.name
  policy_arn = aws_iam_policy.milvus_volume_policy.arn
}

### ==============
### Segurity group
### ==============
resource "aws_security_group" "backend" {
  name        = "${local.name_prefix}-backend"
  description = "Traffic to and from backend"
  vpc_id      = aws_vpc.main.id
}

# Backend API ingress rule from LB
resource "aws_security_group_rule" "backend_api_from_lb" {
  security_group_id = aws_security_group.backend.id

  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lb_sg.id
}

# Backend DB ingress rules from self
# etcd:   2379
# minio:  9000 and 9001
# milvus: 9091 and 19530
resource "aws_security_group_rule" "backend_db_from_self" {
  for_each = toset(["2379", "9000", "9001", "9091", "19530"])

  security_group_id = aws_security_group.backend.id
  type              = "ingress"
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  self              = true
}

# Backend Egress rule
resource "aws_security_group_rule" "backend_all_egress" {
  security_group_id = aws_security_group.backend.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

### ============
### Instance AMI
### ============
data "aws_ssm_parameter" "amazon_linux_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64"
}

### ===============
### Launch template
### ===============
resource "aws_launch_template" "backend" {
  name_prefix = "${local.name_prefix}-backend"

  instance_type = "t2.micro"
  image_id      = data.aws_ssm_parameter.amazon_linux_ami.value
  user_data     = base64encode(file("${path.module}/scripts/backend-user-data.sh"))
  # vpc_security_group_ids = [aws_security_group.backend.id]
  update_default_version = true

  key_name = "jnonino-pac"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.backend.id]
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.backend.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

### ==================
### Auto Scaling Group
### ==================
resource "aws_autoscaling_group" "backend" {
  name_prefix = local.name_prefix

  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  launch_template {
    id      = aws_launch_template.backend.id
    version = aws_launch_template.backend.latest_version
  }

  vpc_zone_identifier = [for subnet in aws_subnet.public : subnet.id]
  target_group_arns   = [aws_lb_target_group.backend.arn]
}
