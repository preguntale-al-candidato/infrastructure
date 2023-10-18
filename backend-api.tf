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

### ==============
### Segurity group
### ==============
# Backend API ingress rule from LB
resource "aws_security_group_rule" "backend_ecs_asg_api_from_lb" {
  security_group_id = aws_security_group.backend_ecs_asg.id

  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lb_sg.id
}

### ==========
### Cloudwatch
### ==========
module "aws_cw_logs" {
  source  = "cn-terraform/cloudwatch-logs/aws"
  version = "1.0.12"

  create_kms_key              = false
  log_group_retention_in_days = 1
  logs_path                   = "/ecs/service/${aws_ecs_cluster.backend.name}-api"
}

### ===============
### Task definition
### ===============
# OpenAI API Key
data "aws_ssm_parameter" "openai_api_key" {
  name = "OPEN_AI_API_KEY"
}

resource "aws_iam_role" "backend_api_task_execution_role" {
  name = "${aws_ecs_cluster.backend.name}-api-task-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole",
      }
    ]
  })
}

resource "aws_iam_role_policy" "backend_api_task_execution_policy" {
  name = "${aws_ecs_cluster.backend.name}-api-task-execution"
  role = aws_iam_role.backend_api_task_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
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
        Effect   = "Allow",
        Action   = ["ssm:DescribeParameters"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["ssm:GetParameter", "ssm:GetParameters"],
        Resource = data.aws_ssm_parameter.openai_api_key.arn
      },
      {
        Effect   = "Allow",
        Action   = ["kms:Decrypt"],
        Resource = data.aws_kms_alias.ssm_default.target_key_arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ecs_task_definition" "backend_api" {
  family                   = "${aws_ecs_cluster.backend.name}-api"
  execution_role_arn       = aws_iam_role.backend_api_task_execution_role.arn
  requires_compatibilities = ["EC2"]
  container_definitions = jsonencode([
    {
      name              = "${local.name_prefix}-backend-api"
      image             = "${var.backend_api_image_name}:${var.backend_api_image_tag}"
      essential         = true
      memoryReservation = 512
      memory            = 1024
      environment = [
        {
          name  = "MILVUS_HOST"
          value = "db-internal.preguntalealcandidato.com"
        },
        {
          name  = "MILVUS_PORT"
          value = "19530"
        },
      ]
      secrets = [
        {
          name      = "OPENAI_API_KEY"
          valueFrom = data.aws_ssm_parameter.openai_api_key.arn
        }
      ]
      portMappings = [
        {
          name          = "backend-api-8000-tcp"
          appProtocol   = "http"
          protocol      = "tcp"
          containerPort = 8000
          hostPort      = 8000
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = module.aws_cw_logs.logs_path
          "awslogs-stream-prefix" = "ecs"
          "awslogs-region"        = data.aws_region.current.name
        }
      }
    }
  ])
}

### ===========
### ECS Service
### ===========
resource "aws_ecs_service" "backend_api" {
  name                               = "${aws_ecs_cluster.backend.name}-api"
  cluster                            = aws_ecs_cluster.backend.id
  task_definition                    = aws_ecs_task_definition.backend_api.arn
  desired_count                      = 2
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 50

  capacity_provider_strategy {
    base              = 1
    capacity_provider = aws_ecs_capacity_provider.backend.name
    weight            = 100
  }

  health_check_grace_period_seconds = 600

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "${local.name_prefix}-backend-api"
    container_port   = 8000
  }
}
