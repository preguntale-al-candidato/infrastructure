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

### ===========
### ECS Cluster
### ===========
resource "aws_ecs_cluster" "backend" {
  name = "${local.name_prefix}-backend"
}

resource "aws_ecs_cluster_capacity_providers" "backend" {
  cluster_name = aws_ecs_cluster.backend.name
  capacity_providers = [aws_ecs_capacity_provider.backend.name]
}

resource "aws_ecs_capacity_provider" "backend" {
  name = "${local.name_prefix}-backend"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = module.autoscaling.autoscaling_group_arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      maximum_scaling_step_size = 1
      minimum_scaling_step_size = 1
      status                    = "DISABLED"
      target_capacity           = 1
    }
  }
}

### ==============
### Segurity group
### ==============
resource "aws_security_group" "backend_ecs_asg" {
  name        = "${local.name_prefix}-backend-ecs-asg"
  description = "Traffic to and from backend ECS ASG"
  vpc_id      = aws_vpc.main.id
}

# Backend API ingress rule from LB
resource "aws_security_group_rule" "backend_ecs_asg_api_from_lb" {
  security_group_id = aws_security_group.backend_ecs_asg.id

  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lb_sg.id
}

# Backend egress rule
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

  name          = "${local.name_prefix}-backend-ecs"
  instance_type = "t2.micro"
  image_id      = jsondecode(data.aws_ssm_parameter.backend_ecs_optimized_ami.value)["image_id"]
  user_data = base64encode(<<-EOT
    #!/bin/bash
    cat <<'EOF' >> /etc/ecs/ecs.config
    ECS_CLUSTER=${aws_ecs_cluster.backend.name}
    ECS_LOGLEVEL=debug
    ECS_ENABLE_TASK_IAM_ROLE=true
    EOF
  EOT
  )

  security_groups     = [aws_security_group.backend_ecs_asg.id]
  vpc_zone_identifier = [for k, v in aws_subnet.private : aws_subnet.private[k].id]

  create_iam_instance_profile = true
  iam_role_name               = "${local.name_prefix}-backend-ecs"
  iam_role_description        = "ECS role for ${aws_ecs_cluster.backend.name}"
  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  health_check_type = "EC2"
  min_size          = 1
  max_size          = 1
  desired_capacity  = 1

  # https://github.com/hashicorp/terraform-provider-aws/issues/12582
  autoscaling_group_tags = {
    AmazonECSManaged = true
  }
}
