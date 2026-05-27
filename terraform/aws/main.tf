locals {
  tags = merge(
    {
      cluster   = var.cluster_name
      project   = var.project
      managedBy = "terraform"
    },
    var.extra_tags,
  )

  # Auto-derive /24 subnets from vpc_cidr when not explicitly provided.
  # Public:  offsets 0–2  → e.g. 10.30.0.0/24, 10.30.1.0/24, 10.30.2.0/24
  # Private: offsets 10–12 → e.g. 10.30.10.0/24, 10.30.11.0/24, 10.30.12.0/24
  public_subnet_cidrs = var.public_subnet_cidrs != null ? var.public_subnet_cidrs : [
    for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 8, i)
  ]
  private_subnet_cidrs = var.private_subnet_cidrs != null ? var.private_subnet_cidrs : [
    for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 10)
  ]
}

module "network" {
  source = "./modules/network"

  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = local.public_subnet_cidrs
  private_subnet_cidrs = local.private_subnet_cidrs
  nat_gateway_count    = var.nat_gateway_count
  operator_ssh_cidrs   = var.operator_ssh_cidrs
  tags                 = local.tags
}

module "compute" {
  source = "./modules/compute"

  cluster_name      = var.cluster_name
  key_name          = var.key_name
  instance_type     = var.instance_type
  instance_count    = var.instance_count
  root_volume_gb    = var.root_volume_gb
  public_subnet_ids = module.network.public_subnet_ids
  private_sg_id     = module.network.private_sg_id
  tags              = local.tags
}
