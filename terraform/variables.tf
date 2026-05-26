variable "env" {
  description = "Environment name (dev | ppe | pro)."
  type        = string

  validation {
    condition     = contains(["dev", "ppe", "pro"], var.env)
    error_message = "env must be one of: dev, ppe, pro."
  }
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name, applied as a tag on every resource."
  type        = string
  default     = "k8s-kubespray"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "azs" {
  description = "Availability zones for subnets (3 required)."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks (3 required, one per AZ)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks (3 required, one per AZ)."
  type        = list(string)
}

variable "nat_gateway_count" {
  description = "Number of NAT gateways (1 = cheap, 3 = HA)."
  type        = number
  default     = 1
}

variable "operator_ssh_cidrs" {
  description = "Source CIDRs allowed to SSH into the bastion."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "key_name" {
  description = "Existing AWS EC2 key pair name."
  type        = string
}

variable "bastion_instance_type" {
  description = "EC2 instance type for the bastion host."
  type        = string
  default     = "t3.micro"
}

variable "node_instance_type" {
  description = "EC2 instance type for the Kubernetes workload nodes."
  type        = string
  default     = "m5.xlarge"
}

variable "node_count" {
  description = "Number of Kubernetes workload nodes."
  type        = number
  default     = 3
}

variable "node_root_volume_gb" {
  description = "Root volume size (GB) for workload nodes."
  type        = number
  default     = 100
}

variable "extra_tags" {
  description = "Additional tags merged into every resource."
  type        = map(string)
  default     = {}
}
