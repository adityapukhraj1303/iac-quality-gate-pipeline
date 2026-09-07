variable "bucket_name" {
  description = "Name of the S3 bucket to store Terraform state"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table to store state locks"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (dev/prod)"
  type        = string
  default     = "shared"
}
