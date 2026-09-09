aws_region         = "ap-south-1"
environment        = "prod"
project_name       = "iac-pipeline"
vpc_cidr           = "10.100.0.0/16"
availability_zones = ["ap-south-1a", "ap-south-1b"]

public_subnet_cidrs  = ["10.100.1.0/24", "10.100.2.0/24"]
private_subnet_cidrs = ["10.100.10.0/24", "10.100.20.0/24"]

cluster_version    = "1.29"
node_instance_type = "t3.small"
desired_nodes      = 3
min_nodes          = 3
max_nodes          = 8

enable_ec2_runner  = true
