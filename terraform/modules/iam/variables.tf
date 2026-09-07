variable "project_name" {
  description = "Project name identifier"
  type        = string
  default     = "iac-pipeline"
}

variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
}
