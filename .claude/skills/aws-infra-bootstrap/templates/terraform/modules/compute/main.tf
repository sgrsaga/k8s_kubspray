locals {
  name_prefix = var.env
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [var.public_sg_id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.bastion_root_volume_gb
    encrypted             = true
    delete_on_termination = true
    tags = merge(var.tags, {
      Name = "${local.name_prefix}-bastion-root"
    })
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-bastion"
    Role = "bastion"
  })
}

resource "aws_instance" "node" {
  count = var.node_count

  ami                    = data.aws_ami.ubuntu_2404.id
  instance_type          = var.node_instance_type
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [var.private_sg_id]
  key_name               = var.key_name

  # MetalLB L2 mode (planned for a later phase) needs source/dest check off so
  # the speaker node can answer ARP for the LB IP without AWS dropping the frame.
  source_dest_check = false

  monitoring = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.node_root_volume_gb
    encrypted             = true
    delete_on_termination = true
    tags = merge(var.tags, {
      Name = "${local.name_prefix}-node-${count.index + 1}-root"
    })
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-node-${count.index + 1}"
    Role = "k8s-node"
  })
}
