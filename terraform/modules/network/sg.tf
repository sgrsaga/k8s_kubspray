resource "aws_security_group" "public" {
  name        = "${local.name_prefix}-public-sg"
  description = "Public-facing SG for bastion: SSH from operator CIDRs."
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-public-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "public_ssh" {
  count = length(var.operator_ssh_cidrs)

  security_group_id = aws_security_group.public.id
  cidr_ipv4         = var.operator_ssh_cidrs[count.index]
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  description       = "SSH from operator CIDR"
}

resource "aws_vpc_security_group_egress_rule" "public_all" {
  security_group_id = aws_security_group.public.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Egress all"
}

resource "aws_security_group" "private" {
  name        = "${local.name_prefix}-private-sg"
  description = "Private SG for k8s nodes: intra-VPC traffic, SSH from bastion only."
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-private-sg"
  })
}

# All intra-SG traffic (node-to-node). Self reference.
resource "aws_vpc_security_group_ingress_rule" "private_self" {
  security_group_id            = aws_security_group.private.id
  referenced_security_group_id = aws_security_group.private.id
  ip_protocol                  = "-1"
  description                  = "All traffic from peers in this SG"
}

# All intra-VPC traffic (covers kubespray's many ports without enumerating).
resource "aws_vpc_security_group_ingress_rule" "private_vpc" {
  security_group_id = aws_security_group.private.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
  description       = "All traffic from within the VPC"
}

# SSH from bastion only.
resource "aws_vpc_security_group_ingress_rule" "private_ssh_from_bastion" {
  security_group_id            = aws_security_group.private.id
  referenced_security_group_id = aws_security_group.public.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  description                  = "SSH from bastion SG"
}

# NodePort 30080 (Kong HTTP). NLB with instance-target preserves client IP,
# so the instance SG sees the original client source — accept from anywhere.
# Health checks from the NLB also fall under this rule.
resource "aws_vpc_security_group_ingress_rule" "private_nodeport_http" {
  security_group_id = aws_security_group.private.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 30080
  to_port           = 30080
  description       = "Kong HTTP NodePort (NLB → node)"
}

# NodePort 30443 (Kong HTTPS, TLS terminated at Kong). Same client-IP rationale.
resource "aws_vpc_security_group_ingress_rule" "private_nodeport_https" {
  security_group_id = aws_security_group.private.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 30443
  to_port           = 30443
  description       = "Kong HTTPS NodePort (NLB → node)"
}

resource "aws_vpc_security_group_egress_rule" "private_all" {
  security_group_id = aws_security_group.private.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Egress all"
}
