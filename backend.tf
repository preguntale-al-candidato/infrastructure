#########################################
# IAM user to deploy new backend versions
#########################################

resource "aws_iam_user" "backend_deployer_user" {
  name          = "backend-deployer"
  force_destroy = true
}
