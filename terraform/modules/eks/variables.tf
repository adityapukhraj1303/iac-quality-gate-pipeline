variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes control plane version"
  type        = string
  default     = "1.29"
}

variable "vpc_id" {
  description = "VPC ID where EKS is deployed"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for EKS control plane (must span at least 2 AZs)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private Subnets for worker nodes"
  type        = list(string)
}

variable "cluster_role_arn" {
  description = "ARN of IAM role for EKS control plane"
  type        = string
}

variable "node_role_arn" {
  description = "ARN of IAM role for EKS worker nodes"
  type        = string
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "desired_node_count" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "min_node_count" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "max_node_count" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 5
}

variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
}
