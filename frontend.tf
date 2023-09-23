############
# S3 Website
############
module "website" {
  providers = {
    aws.main         = aws
    aws.acm_provider = aws.acm_provider
  }

  source  = "cn-terraform/s3-static-website/aws"
  version = "1.0.8"

  name_prefix         = local.name_prefix
  website_domain_name = local.domain_name

  create_acm_certificate     = false
  acm_certificate_arn_to_use = aws_acm_certificate.cert.arn

  create_route53_hosted_zone = false
  route53_hosted_zone_id     = module.route53.zone_id
}

#########################################
# IAM user to deploy new website versions
#########################################

resource "aws_iam_user" "website_deployer_user" {
  name          = "website-deployer"
  force_destroy = true
}

resource "aws_iam_policy" "website_deployer_policy" {
  name        = "website-deployer"
  description = "Permissions to deploy to the S3 website"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [module.website.website_bucket_arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = ["${module.website.website_bucket_arn}/*"]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "test-attach" {
  user       = aws_iam_user.website_deployer_user.name
  policy_arn = aws_iam_policy.website_deployer_policy.arn
}
