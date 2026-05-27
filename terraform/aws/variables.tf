variable "cluster_name" {
  description = "Cluster identifier — injected automatically by tf.sh from the tfvars filename. Do not set this in tfvars files."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name, applied as a tag on every resource."
  type        = string
  default     = "k8s-multicluster"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Each cluster must use a unique, non-overlapping CIDR."
  type        = string
}

variable "azs" {
  description = "Availability zones for subnets (3 required). Defaults to all three AZs in ap-south-1."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]

  validation {
    condition     = length(var.azs) == 3
    error_message = "Exactly 3 availability zones are required."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks (one per AZ). If null, derived automatically from vpc_cidr using /24 slices at offsets 0-2."
  type        = list(string)
  default     = null

  validation {
    condition     = var.public_subnet_cidrs == null || length(var.public_subnet_cidrs) == 3
    error_message = "public_subnet_cidrs must be null (auto-derive) or a list of exactly 3 CIDRs."
  }
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks (one per AZ). If null, derived automatically from vpc_cidr using /24 slices at offsets 10-12."
  type        = list(string)
  default     = null

  validation {
    condition     = var.private_subnet_cidrs == null || length(var.private_subnet_cidrs) == 3
    error_message = "private_subnet_cidrs must be null (auto-derive) or a list of exactly 3 CIDRs."
  }
}

variable "nat_gateway_count" {
  description = "Number of NAT gateways. 1 = single (cheap, dev/ppe). 3 = one per AZ (HA, production)."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3], var.nat_gateway_count)
    error_message = "nat_gateway_count must be 1 or 3."
  }
}

variable "operator_ssh_cidrs" {
  description = "Source CIDRs allowed to SSH via the public security group."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "key_name" {
  description = "Existing AWS EC2 key pair name in the target region."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the k8s nodes."
  type        = string
  default     = "m5.large"
}

variable "instance_count" {
  description = "Number of k8s nodes. Use a multiple of the AZ count (3) for even distribution across availability zones."
  type        = number
  default     = 3

  validation {
    condition     = var.instance_count > 0
    error_message = "instance_count must be at least 1."
  }
}

variable "root_volume_gb" {
  description = "Root volume size (GB) for each node."
  type        = number
  default     = 100
}

variable "extra_tags" {
  description = "Additional tags merged into every resource."
  type        = map(string)
  default     = {}
}
