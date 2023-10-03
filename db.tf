####################################
# S3 bucket for Milvus volume backup
####################################
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
