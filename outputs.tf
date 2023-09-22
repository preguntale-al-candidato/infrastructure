#########
# Route53
#########
output "route53" {
  value = module.route53
}

############
# S3 Website
############
output "website" {
  value = module.website
}

#########################################
# IAM user to deploy new website versions
#########################################
output "website_deployer_user" {
  value = aws_iam_user.website_deployer_user
}

output "website_deployer_policy" {
  value = aws_iam_policy.website_deployer_policy
}
