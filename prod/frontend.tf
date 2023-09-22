###################
# Temporary website
###################
module "website" {
  providers = {
    aws.main         = aws.main
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
