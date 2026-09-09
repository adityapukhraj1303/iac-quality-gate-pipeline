# ==============================================================================
# S3 Remote State Backend with DynamoDB State Locking
# ==============================================================================
# In production, replace the bucket and dynamodb_table names with the ones
# created by the s3-backend module (or your pre-existing state bucket).

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Commented for initial local bootstrap; uncomment once backend bucket is created:
  # backend "s3" {
  #   bucket         = "iac-pipeline-terraform-state-backend"
  #   key            = "state/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "iac-pipeline-terraform-state-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
