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
      configuration_aliases = [aws.main, aws.acm_provider]
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  alias  = "main"
  region = "eu-west-2"
}

provider "aws" {
  alias  = "acm_provider"
  region = "us-east-1"
}
