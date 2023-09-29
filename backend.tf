#########################################
# IAM user to deploy new backend versions
#########################################

resource "aws_iam_user" "backend_deployer_user" {
  name          = "backend-deployer"
  force_destroy = true
}

#######################################
# Elastic Container Registry Repository
#######################################
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

####################
# Auto Scaling Group
####################
# resource "aws_autoscaling_group" "backend" {
#   # Launch config, VPC zone ids, etc

#   target_group_arns = [aws_lb_target_group.backend.arn]
# }

##############################
# Load balancing configuration
##############################

# Target Group
resource "aws_lb_target_group" "backend" {
  # Other config

  protocol = "HTTP"
  port     = 80
  vpc_id   = module.networking.vpc_id
}

# Attachment
# resource "aws_autoscaling_attachment" "backend_asg_lb_attachment" {
#   autoscaling_group_name = aws_autoscaling_group.backend.id
#   alb_target_group_arn   = aws_lb_target_group.backend.arn
# }

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

# ALB listener rule
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    host_header {
      values = [aws_route53_record.api.name]
    }
  }
}
