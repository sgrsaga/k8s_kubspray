output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability zones used by the subnets."
  value       = var.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs, ordered to match azs."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, ordered to match azs."
  value       = aws_subnet.private[*].id
}

output "public_sg_id" {
  description = "Security group ID for public-facing resources (bastion)."
  value       = aws_security_group.public.id
}

output "private_sg_id" {
  description = "Security group ID for private resources (k8s nodes)."
  value       = aws_security_group.private.id
}

output "internet_gateway_id" {
  description = "Internet gateway ID."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs."
  value       = aws_nat_gateway.this[*].id
}
