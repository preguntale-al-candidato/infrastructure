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

  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 300
    unhealthy_threshold = 3
    path                = "/health"
    matcher             = "200"
  }
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

### ===========
### ECS Cluster
### ===========
resource "aws_ecs_cluster" "backend" {
  name = "${local.name_prefix}-backend"
}

resource "aws_ecs_capacity_provider" "backend" {
  name = aws_ecs_cluster.backend.name

  auto_scaling_group_provider {
    auto_scaling_group_arn         = module.autoscaling.autoscaling_group_arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      status                    = "ENABLED"
      maximum_scaling_step_size = 1
      minimum_scaling_step_size = 1
      target_capacity           = 1
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "backend" {
  cluster_name       = aws_ecs_cluster.backend.name
  capacity_providers = [aws_ecs_capacity_provider.backend.name]
  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.backend.name
  }
}

### ==============
### Segurity group
### ==============
resource "aws_security_group" "backend_ecs_asg" {
  name        = "${aws_ecs_cluster.backend.name}-ecs-asg"
  description = "Traffic to and from backend ECS ASG"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group_rule" "backend_ecs_asg_all_egress" {
  security_group_id = aws_security_group.backend_ecs_asg.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

### ===============
### Autoscaling ECS
### ===============

# ECS Optimized AMI
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html
data "aws_ssm_parameter" "backend_ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended"
}

module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 6.5"

  name          = "${aws_ecs_cluster.backend.name}-ecs"
  instance_type = "t2.micro"
  image_id      = jsondecode(data.aws_ssm_parameter.backend_ecs_optimized_ami.value)["image_id"]
  user_data = base64encode(<<-EOT
    #!/bin/bash
    cat <<'EOF' >> /etc/ecs/ecs.config
    ECS_CLUSTER=${aws_ecs_cluster.backend.name}
    EOF
  EOT
  )

  key_name            = "jnonino-pac"
  security_groups     = [aws_security_group.backend_ecs_asg.id]
  vpc_zone_identifier = [for k, v in aws_subnet.public : aws_subnet.public[k].id]
  network_interfaces = [
    {
      associate_public_ip_address = true
      security_groups             = [aws_security_group.backend.id]
    }
  ]

  create_iam_instance_profile = true
  iam_role_name               = "${local.name_prefix}-backend-ecs"
  iam_role_description        = "ECS role for ${aws_ecs_cluster.backend.name}"
  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

    # {
    #     Effect   = "Allow"
    #     Action   = ["ecr:GetAuthorizationToken"]
    #     Resource = "*"
    #   },
    #   {
    #     Effect = "Allow"
    #     Action = [
    #       "ecr:BatchCheckLayerAvailability",
    #       "ecr:GetDownloadUrlForLayer",
    #       "ecr:GetRepositoryPolicy",
    #       "ecr:DescribeRepositories",
    #       "ecr:ListImages",
    #       "ecr:DescribeImages",
    #       "ecr:BatchGetImage"
    #     ]
    #     Resource = [aws_ecr_repository.backend.arn]
    #   },
  }

  health_check_type = "EC2"
  min_size          = 1
  max_size          = 1
  desired_capacity  = 1
  enable_monitoring = false

  # Required for  managed_termination_protection = "ENABLED"
  protect_from_scale_in = true

  # https://github.com/hashicorp/terraform-provider-aws/issues/12582
  autoscaling_group_tags = {
    AmazonECSManaged = true
  }
}
