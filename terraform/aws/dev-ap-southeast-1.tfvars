cluster_name = "dev-ap-southeast-1"
region       = "ap-southeast-1"
project      = "k8s-singapore"

vpc_cidr = "10.31.0.0/16"
# azs and subnet CIDRs auto-derived from vpc_cidr; override only if needed


nat_gateway_count  = 1
operator_ssh_cidrs = ["172.216.151.12/32"]

key_name       = "singapore" # name of existing AWS keypair in this region
instance_type  = "c5a.xlarge"
instance_count = 1
root_volume_gb = 100
