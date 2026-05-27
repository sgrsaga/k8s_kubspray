cluster_name = "dev-ap-south-1"
region       = "ap-south-1"
project      = "k8s-multicluster"

vpc_cidr = "10.30.0.0/16"
# azs and subnet CIDRs auto-derived from vpc_cidr; override only if needed

nat_gateway_count  = 1
operator_ssh_cidrs = ["172.216.151.12/32"]

key_name       = "mumbai" # name of existing AWS keypair in this region
instance_type  = "c5a.xlarge"
instance_count = 1
root_volume_gb = 100
