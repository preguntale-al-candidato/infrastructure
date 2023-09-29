terraform {
  cloud {
    organization = "preguntale-al-candidato"
    workspaces {
      name = "prod"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS provider
provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Name        = local.name_prefix
      Environment = "Prod"
      Owner       = "craneando.co.uk"
      Service     = "preguntale-al-candidato"
    }
  }
}
