env     = "ppe"
region  = "ap-south-1"
project = "k8s-kubespray"

vpc_cidr             = "10.40.0.0/16"
azs                  = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
public_subnet_cidrs  = ["10.40.0.0/24", "10.40.1.0/24", "10.40.2.0/24"]
private_subnet_cidrs = ["10.40.10.0/24", "10.40.11.0/24", "10.40.12.0/24"]

nat_gateway_count = 1

# Tighten this to office/CI/VPN CIDRs once known.
operator_ssh_cidrs = ["0.0.0.0/0"]

key_name              = "CHANGE_ME" # name of an existing AWS keypair in this region
bastion_instance_type = "t3.micro"
node_instance_type    = "m5.xlarge"
node_count            = 3
node_root_volume_gb   = 100
