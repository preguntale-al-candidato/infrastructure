###################################
# S3 bucket to store transcriptions
###################################
resource "aws_s3_bucket" "transcriptions" {
  bucket        = "transcriptions-pac"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "transcriptions" {
  bucket = aws_s3_bucket.transcriptions.id
  versioning_configuration {
    status     = "Enabled"
    mfa_delete = "Disabled"
  }
}

###################################
# IAM user to upload transcriptions
###################################
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
