env     = "pro"
region  = "ap-south-1"
project = "k8s-kubespray"

vpc_cidr             = "10.50.0.0/16"
azs                  = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
public_subnet_cidrs  = ["10.50.0.0/24", "10.50.1.0/24", "10.50.2.0/24"]
private_subnet_cidrs = ["10.50.10.0/24", "10.50.11.0/24", "10.50.12.0/24"]

# HA NAT for pro: one per AZ.
nat_gateway_count = 3

# REPLACE with actual office / CI / VPN CIDRs before applying pro.
operator_ssh_cidrs = ["0.0.0.0/0"]

key_name              = "CHANGE_ME" # name of an existing AWS keypair in this region
bastion_instance_type = "t3.micro"
node_instance_type    = "m5.2xlarge"
node_count            = 3
node_root_volume_gb   = 200
