variable "cluster_name" {
  description = "Cluster identifier used as resource name prefix and tag."
  type        = string
}

variable "key_name" {
  description = "Name of an existing AWS EC2 key pair used to log into the instances."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the k8s nodes."
  type        = string
  default     = "m5.large"
}

variable "instance_count" {
  description = "Number of k8s nodes to create."
  type        = number
  default     = 2
}

variable "root_volume_gb" {
  description = "Root volume size (GB) for each node."
  type        = number
  default     = 100
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (from networking module). Nodes are distributed round-robin."
  type        = list(string)
}

variable "private_sg_id" {
  description = "Security group ID for the k8s nodes."
  type        = string
}

variable "tags" {
  description = "Tags merged into every resource."
  type        = map(string)
  default     = {}
}
