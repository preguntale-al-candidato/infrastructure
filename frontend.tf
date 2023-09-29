#################
# ACM Certificate
#################
resource "aws_acm_certificate" "cert_cloudfront" {
  provider = aws.acm_provider

  domain_name               = "*.${local.domain_name}"
  subject_alternative_names = [local.domain_name]
  validation_method         = "DNS"
  tags = {
    Name = local.domain_name
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_cloudfront_validation_records" {
  for_each = {
    for dvo in aws_acm_certificate.cert_cloudfront.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 300
  type            = each.value.type
  zone_id         = module.route53.zone_id
}

resource "aws_acm_certificate_validation" "cert_cloudfront_validation" {
  provider = aws.acm_provider

  # Dependency to guarantee that certificate and DNS records are created before this resource
  depends_on = [
    aws_acm_certificate.cert_cloudfront,
    aws_route53_record.cert_cloudfront_validation_records,
  ]

  certificate_arn         = aws_acm_certificate.cert_cloudfront.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_cloudfront_validation_records : record.fqdn]
}

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
  acm_certificate_arn_to_use = aws_acm_certificate.cert_cloudfront.arn

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

resource "aws_iam_user_policy_attachment" "website_deployer_policy_attach" {
  user       = aws_iam_user.website_deployer_user.name
  policy_arn = aws_iam_policy.website_deployer_policy.arn
}
