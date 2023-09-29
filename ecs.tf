#################
# Base networking
#################
module "networking" {
  source  = "cn-terraform/networking/aws"
  version = "3.0.0"

  cidr_block = "172.16.0.0/16"
  single_nat = true

  public_subnets = {
    first_public_subnet = {
      availability_zone = "eu-west-2a"
      cidr_block        = "172.16.0.0/18"
    }
    second_public_subnet = {
      availability_zone = "eu-west-2b"
      cidr_block        = "172.16.64.0/18"
    }
  }

  private_subnets = {
    first_private_subnet = {
      availability_zone = "eu-west-2a"
      cidr_block        = "172.16.128.0/18"
    }
    second_private_subnet = {
      availability_zone = "eu-west-2b"
      cidr_block        = "172.16.192.0/18"
    }
  }
}

###################
# Autoscaling group
###################

#############
# ECS Cluster
#############
module "ecs-cluster" {
  source  = "cn-terraform/ecs-cluster/aws"
  version = "1.0.11"

  name = local.name_prefix
}
