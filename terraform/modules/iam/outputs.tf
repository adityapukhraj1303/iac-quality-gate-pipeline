output "eks_cluster_role_arn" {
  description = "ARN of the EKS Cluster control plane IAM role"
  value       = aws_iam_role.eks_cluster_role.arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS Worker Nodes IAM role"
  value       = aws_iam_role.eks_node_role.arn
}

output "ci_runner_profile_name" {
  description = "Name of the IAM Instance Profile for CI runners"
  value       = aws_iam_instance_profile.ci_runner_profile.name
}

output "ci_runner_role_arn" {
  description = "ARN of the CI Runner IAM role"
  value       = aws_iam_role.ci_runner_role.arn
}
