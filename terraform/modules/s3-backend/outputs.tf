output "bucket_name" {
  description = "The name of the state S3 bucket"
  value       = aws_s3_bucket.state_bucket.id
}

output "bucket_arn" {
  description = "The ARN of the state S3 bucket"
  value       = aws_s3_bucket.state_bucket.arn
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB lock table"
  value       = aws_dynamodb_table.state_locks.name
}
