variable "env" {
  description = "Environment name (dev | ppe | pro)."
  type        = string
}

variable "key_name" {
  description = "Name of an existing AWS EC2 key pair (in the target region) used to log into the instances."
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

variable "bastion_root_volume_gb" {
  description = "Root volume size (GB) for the bastion host."
  type        = number
  default     = 20
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (from network module). Bastion lands in index 0."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs (from network module). Nodes are spread round-robin across these."
  type        = list(string)
}

variable "public_sg_id" {
  description = "Security group ID for the bastion."
  type        = string
}

variable "private_sg_id" {
  description = "Security group ID for the workload nodes."
  type        = string
}

variable "tags" {
  description = "Tags merged into every resource."
  type        = map(string)
  default     = {}
}
