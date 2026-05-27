locals {
  name_prefix = var.cluster_name
}

resource "aws_instance" "node" {
  count = var.instance_count

  ami           = data.aws_ami.ubuntu_2404.id
  instance_type = var.instance_type

  subnet_id                   = var.public_subnet_ids[count.index % length(var.public_subnet_ids)]
  associate_public_ip_address = true
  vpc_security_group_ids      = [var.private_sg_id]
  key_name                    = var.key_name

  monitoring = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_gb
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
