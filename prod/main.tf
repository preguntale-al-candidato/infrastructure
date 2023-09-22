#########
# Route53
#########
module "route53" {
  source  = "cn-terraform/route53/aws"
  version = "0.0.1"

  create_hosted_zone = true
  hosted_zone_name   = "preguntalealcandidato.com"
  records            = {}
}
