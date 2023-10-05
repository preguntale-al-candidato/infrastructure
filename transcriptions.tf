### =================================
### S3 bucket to store transcriptions
### =================================
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
