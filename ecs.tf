#############
# ECS Cluster
#############
module "ecs-cluster" {
  source  = "cn-terraform/ecs-cluster/aws"
  version = "1.0.11"

  name = local.name_prefix
}
