output "instance_id" {
  description = "The ID of the CI Runner EC2 instance"
  value       = aws_instance.runner.id
}

output "private_ip" {
  description = "Private IP address of the instance"
  value       = aws_instance.runner.private_ip
}

output "ssm_connect_command" {
  description = "Command to connect via AWS SSM Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.runner.id}"
}
