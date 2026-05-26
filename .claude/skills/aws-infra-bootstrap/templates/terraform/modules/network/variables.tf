variable "env" {
  description = "Environment name (dev | ppe | pro). Used as resource name prefix and tag."
  type        = string

  validation {
    condition     = contains(["dev", "ppe", "pro"], var.env)
    error_message = "env must be one of: dev, ppe, pro."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC, e.g. 10.30.0.0/16."
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across. Length must equal the subnet CIDR list lengths."
  type        = list(string)

  validation {
    condition     = length(var.azs) == 3
    error_message = "Exactly 3 AZs are required."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets, one per AZ."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 3
    error_message = "Exactly 3 public subnet CIDRs are required."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets, one per AZ."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == 3
    error_message = "Exactly 3 private subnet CIDRs are required."
  }
}

variable "nat_gateway_count" {
  description = "Number of NAT Gateways. 1 = single (cheap, single-AZ failure domain). 3 = one per AZ (HA)."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3], var.nat_gateway_count)
    error_message = "nat_gateway_count must be 1 or 3."
  }
}

variable "operator_ssh_cidrs" {
  description = "Source CIDR blocks allowed to SSH (port 22) to the bastion."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Tags merged into every resource."
  type        = map(string)
  default     = {}
}
