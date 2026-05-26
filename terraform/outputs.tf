output "vpc_id" {
  description = "ID of the VPC."
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = module.network.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs (parallel to azs)."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs (parallel to azs)."
  value       = module.network.private_subnet_ids
}

output "public_sg_id" {
  value = module.network.public_sg_id
}

output "private_sg_id" {
  value = module.network.private_sg_id
}

output "bastion_public_ip" {
  description = "Public IP of the bastion. Use this with `ssh -J ubuntu@<bastion>` to reach private nodes."
  value       = module.compute.bastion_public_ip
}

output "bastion_public_dns" {
  value = module.compute.bastion_public_dns
}

output "node_private_ips" {
  description = "Private IPs of Kubernetes workload nodes (use as kubespray ansible_host)."
  value       = module.compute.node_private_ips
}

output "node_public_ips" {
  description = "Public IPs of Kubernetes workload nodes. Set Route53 A records for env subdomains to these IPs (clients hit https://host:30443)."
  value       = module.compute.node_public_ips
}

output "node_instance_ids" {
  value = module.compute.node_instance_ids
}

output "node_availability_zones" {
  value = module.compute.node_availability_zones
}

output "ami_id" {
  description = "Resolved Ubuntu 24.04 LTS AMI."
  value       = module.compute.ami_id
}
