output "node_instance_ids" {
  description = "EC2 instance IDs of the k8s nodes."
  value       = aws_instance.node[*].id
}

output "node_private_ips" {
  description = "Private IPs of the k8s nodes."
  value       = aws_instance.node[*].private_ip
}

output "node_public_ips" {
  description = "Public IPs of the k8s nodes."
  value       = aws_instance.node[*].public_ip
}

output "node_availability_zones" {
  description = "AZs of the k8s nodes (parallel to node_private_ips)."
  value       = aws_instance.node[*].availability_zone
}

output "ami_id" {
  description = "Resolved Ubuntu 24.04 LTS AMI ID."
  value       = data.aws_ami.ubuntu_2404.id
}
