variable "project_name" {
  description = "Project name identifier"
  type        = string
  default     = "iac-pipeline"
}

variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where runner is deployed"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for runner instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "instance_profile_name" {
  description = "IAM Instance profile name with SSM permissions"
  type        = string
}
