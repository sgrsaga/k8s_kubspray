output "bastion_instance_id" {
  description = "EC2 instance ID of the bastion."
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host."
  value       = aws_instance.bastion.public_ip
}

output "bastion_public_dns" {
  description = "Public DNS name of the bastion host."
  value       = aws_instance.bastion.public_dns
}

output "node_instance_ids" {
  description = "EC2 instance IDs of the Kubernetes workload nodes."
  value       = aws_instance.node[*].id
}

output "node_private_ips" {
  description = "Private IPs of the Kubernetes workload nodes."
  value       = aws_instance.node[*].private_ip
}

output "node_availability_zones" {
  description = "AZs of the Kubernetes workload nodes (parallel to node_private_ips)."
  value       = aws_instance.node[*].availability_zone
}

output "ami_id" {
  description = "Resolved Ubuntu 24.04 LTS AMI ID."
  value       = data.aws_ami.ubuntu_2404.id
}
