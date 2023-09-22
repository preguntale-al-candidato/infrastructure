########
# Locals
########
locals {
  name_prefix = "pac"
  domain_name = "preguntalealcandidato.com"
}

#########
# Route53
#########
module "route53" {
  providers = {
    aws = aws.main
  }

  source  = "cn-terraform/route53/aws"
  version = "0.0.1"

  create_hosted_zone = true
  hosted_zone_name   = local.domain_name
  records            = {}
}

#################
# ACM Certificate
#################
resource "aws_acm_certificate" "cert" {
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

resource "aws_route53_record" "acm_certificate_validation_records" {
  provider = aws.main

  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
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

resource "aws_acm_certificate_validation" "cert_validation" {
  provider = aws.acm_provider

  # Dependency to guarantee that certificate and DNS records are created before this resource
  depends_on = [
    aws_acm_certificate.cert,
    aws_route53_record.acm_certificate_validation_records,
  ]

  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_certificate_validation_records : record.fqdn]
}
