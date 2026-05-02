terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.15.0"
    }
  }
  required_version = ">=1.10.0"
}

provider "aws" {
  # Configuration options
  region = "eu-central-1"
  default_tags {
    tags = var.tags
  }

}
