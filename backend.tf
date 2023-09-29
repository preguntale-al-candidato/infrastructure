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
