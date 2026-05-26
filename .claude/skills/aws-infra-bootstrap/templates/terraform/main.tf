locals {
  tags = merge(
    {
      env       = var.env
      project   = var.project
      managedBy = "terraform"
    },
    var.extra_tags,
  )
}

module "network" {
  source = "./modules/network"

  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  nat_gateway_count    = var.nat_gateway_count
  operator_ssh_cidrs   = var.operator_ssh_cidrs
  tags                 = local.tags
}

module "compute" {
  source = "./modules/compute"

  env                   = var.env
  key_name              = var.key_name
  bastion_instance_type = var.bastion_instance_type
  node_instance_type    = var.node_instance_type
  node_count            = var.node_count
  node_root_volume_gb   = var.node_root_volume_gb
  public_subnet_ids     = module.network.public_subnet_ids
  private_subnet_ids    = module.network.private_subnet_ids
  public_sg_id          = module.network.public_sg_id
  private_sg_id         = module.network.private_sg_id
  tags                  = local.tags
}
