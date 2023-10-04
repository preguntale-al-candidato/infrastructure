### =================================
### IAM user to upload transcriptions
### =================================
resource "aws_iam_user" "transcriptions_uploader_user" {
  name          = "transcriptions-uploader"
  force_destroy = true
}

resource "aws_iam_policy" "transcriptions_uploader_policy" {
  name        = "transcriptions-uploader"
  description = "Permissions to upload to the S3 bucket"
  policy = templatefile("${path.module}/templates/bucket_sync_policy.json", {
    bucketArn = aws_s3_bucket.transcriptions.arn
  })
}

resource "aws_iam_user_policy_attachment" "transcriptions_uploader_policy_attach" {
  user       = aws_iam_user.transcriptions_uploader_user.name
  policy_arn = aws_iam_policy.transcriptions_uploader_policy.arn
}

### ==================================
### S3 bucket for Milvus volume backup
### ==================================
resource "aws_s3_bucket" "milvus_volume" {
  bucket        = "milvus-volume"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "milvus_volume" {
  bucket = aws_s3_bucket.milvus_volume.id
  versioning_configuration {
    status     = "Enabled"
    mfa_delete = "Disabled"
  }
}

resource "aws_iam_policy" "milvus_volume_policy" {
  name        = "milvus_volume"
  description = "Permissions to upload to the Milvus Volume buckets"
  policy = templatefile("${path.module}/templates/bucket_sync_policy.json", {
    bucketArn = aws_s3_bucket.milvus_volume.arn
  })
}

### =======================================
### IAM user to deploy new backend versions
### =======================================
resource "aws_iam_user" "backend_deployer_user" {
  name          = "backend-deployer"
  force_destroy = true
}

resource "aws_iam_policy" "backend_deployer_policy" {
  name        = "backend-deployer"
  description = "Permissions to deploy to the Backend ECR repository"
  policy = jsonencode({
    Version = "2012-10-17"
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
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = [aws_ecr_repository.backend.arn]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "backend_deployer_policy_attach" {
  user       = aws_iam_user.backend_deployer_user.name
  policy_arn = aws_iam_policy.backend_deployer_policy.arn
}

### =======================================
### IAM user to deploy new website versions
### =======================================
resource "aws_iam_user" "website_deployer_user" {
  name          = "website-deployer"
  force_destroy = true
}

resource "aws_iam_policy" "website_deployer_policy" {
  name        = "website-deployer"
  description = "Permissions to deploy to the S3 website"
  policy = templatefile("${path.module}/templates/bucket_sync_policy.json", {
    bucketArn = module.website.website_bucket_arn
  })
}

resource "aws_iam_user_policy_attachment" "website_deployer_policy_attach" {
  user       = aws_iam_user.website_deployer_user.name
  policy_arn = aws_iam_policy.website_deployer_policy.arn
}
