aws_region         = "ap-south-1"
environment        = "dev"
project_name       = "iac-pipeline"
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["ap-south-1a", "ap-south-1b"]

public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]

cluster_version    = "1.29"
node_instance_type = "t3.small"
desired_nodes      = 2
min_nodes          = 2
max_nodes          = 4

enable_ec2_runner  = true
