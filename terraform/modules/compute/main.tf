locals {
  name_prefix = var.env
}


resource "aws_instance" "node" {
  count = var.node_count

  ami           = data.aws_ami.ubuntu_2404.id
  instance_type = var.node_instance_type

  # Nodes live in PUBLIC subnets so Route53 can resolve directly to them.
  # Clients hit https://<host>:30443 — NodePort 30080/30443 on the node SG
  # is open to 0.0.0.0/0. SSH 22 stays restricted to the bastion SG only.
  subnet_id                   = var.public_subnet_ids[count.index % length(var.public_subnet_ids)]
  associate_public_ip_address = true
  vpc_security_group_ids      = [var.private_sg_id]
  key_name                    = var.key_name

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
