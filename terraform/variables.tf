variable "aws_region" {
  description = "AWS Region for resource deployment"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Target deployment environment (dev or prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name prefix for tags and resource names"
  type        = string
  default     = "iac-pipeline"
}

variable "vpc_cidr" {
  description = "VPC network CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for multi-AZ deployment"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.29"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.small"
}

variable "desired_nodes" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "min_nodes" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "max_nodes" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 5
}

variable "enable_ec2_runner" {
  description = "Whether to provision a dedicated EC2 CI/CD runner instance"
  type        = bool
  default     = true
}
