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

############
# Networking
############
module "networking" {
  source  = "cn-terraform/networking/aws"
  version = "3.0.0"

  cidr_block = "172.16.0.0/16"
  single_nat = true

  public_subnets = {
    public_subnet_a = {
      availability_zone = "eu-west-2a"
      cidr_block        = "172.16.0.0/18"
    }
    # public_subnet_b = {
    #   availability_zone = "eu-west-2b"
    #   cidr_block        = "172.16.64.0/18"
    # }
  }

  private_subnets = {
    private_subnet_a = {
      availability_zone = "eu-west-2a"
      cidr_block        = "172.16.128.0/18"
    }
    # private_subnet_b = {
    #   availability_zone = "eu-west-2b"
    #   cidr_block        = "172.16.192.0/18"
    # }
  }
}

################
# Load Balancing
################
# Load Balancer security group
resource "aws_security_group" "lb_sg" {
  name        = "${local.name_prefix}-lb"
  description = "Allow HTTPS to ALB"
  vpc_id      = module.networking.vpc_id
}

# LB HTTPS Ingress rule
resource "aws_security_group_rule" "lb_https_ingress" {
  security_group_id = aws_security_group.lb_sg.id

  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

# LB Egress rule
resource "aws_security_group_rule" "lb_all_egress" {
  security_group_id = aws_security_group.lb_sg.id

  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

# Application Load Balancer
resource "aws_lb" "lb" {
  name               = local.name_prefix
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = [for subnet in module.networking.public_subnets : subnet.id]

  enable_deletion_protection = false
}

# HTTPS ALB listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Default response not implemented"
      status_code  = "501"
    }
  }
}
