### ======
### Locals
### ======
locals {
  name_prefix = "pac"
  domain_name = "preguntalealcandidato.com"

  vpc_cidr_block = "172.16.0.0/16"

  public_subnets = {
    public_subnet_az_a = {
      availability_zone = "us-east-1a"
      cidr_block        = "172.16.0.0/18"
    }
    public_subnet_az_b = {
      availability_zone = "us-east-1b"
      cidr_block        = "172.16.64.0/18"
    }
  }

  private_subnets = {
    private_subnet_az_a = {
      availability_zone = "us-east-1a"
      cidr_block        = "172.16.128.0/18"
    }
    private_subnet_az_b = {
      availability_zone = "us-east-1b"
      cidr_block        = "172.16.192.0/18"
    }
  }
}
