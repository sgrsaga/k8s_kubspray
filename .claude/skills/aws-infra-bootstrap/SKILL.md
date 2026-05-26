---
name: aws-infra-bootstrap
description: |
  Phase 1 of this project: provision the per-env AWS infrastructure (VPC,
  subnets, NAT, bastion, EC2 nodes) that the kubespray cluster will run on.
  Use when the user asks to set up AWS infra, apply Terraform for an env
  (dev/ppe/pro), bootstrap the state bucket, or scaffold the Terraform
  modules from these templates into the repo. Triggers on: "AWS infra for
  this project", "apply terraform for <env>", "bootstrap dev/ppe/pro VPCs",
  "Phase 1", "set up the Terraform modules".
---

# AWS Infrastructure for Kubespray Kubernetes (multi-env)

This skill provisions production-shaped AWS infrastructure for a self-managed
Kubernetes cluster bootstrapped by **kubespray**. Same blueprint for every
tenant/environment — only `*.tfvars` changes.

## What it builds

Per environment (`dev`, `ppe`, `pro`), one isolated VPC containing:

- VPC + Internet Gateway
- 3 public + 3 private subnets, one per AZ
- NAT Gateway(s): **1** (cheap, dev/ppe) or **3** (HA, pro), driven by `nat_gateway_count`
- Public security group (bastion: SSH from `operator_ssh_cidrs`)
- Private security group (nodes: intra-VPC + SSH from bastion only)
- 1× bastion EC2 (`t3.micro`, public subnet)
- 3× workload EC2s (CP+worker nodes, private subnets, IMDSv2-only,
  source/dest-check off, gp3 encrypted root)
- Ubuntu 24.04 LTS via Canonical AMI lookup
- S3 backend with **native locking** (`use_lockfile = true` — no DynamoDB)

**Not included** (deliberate): no AWS NLB/ALB, no IAM-for-pods, no Route53.
Cluster API HA is via kubespray's local haproxy on each node
(`loadbalancer_apiserver_localhost: true`). In-cluster LoadBalancer services
will come from MetalLB once the cluster is up.

## Layout

```
terraform/
├── versions.tf, providers.tf, variables.tf, main.tf, outputs.tf
├── modules/
│   ├── network/   # VPC, IGW, subnets, NAT, route tables, public+private SGs
│   └── compute/   # bastion + workload EC2 nodes, Ubuntu 24.04 AMI lookup
├── backends/
│   ├── dev.hcl, ppe.hcl, pro.hcl       # one S3 state key per env
└── dev.tfvars, ppe.tfvars, pro.tfvars  # per-env values (the only thing that differs)
```

## How to use this skill

When invoked, follow these steps **in order**.

### Step 1 — Confirm scope with the user

Ask only what isn't obvious from context. The defaults below are reasonable;
confirm or override:

- **Region** (default `ap-south-1`)
- **AWS keypair name** that exists in that region (no default — required, used for SSH to bastion + nodes)
- **State bucket name** (globally unique S3 bucket, must already exist)
- **Environments** to deploy (default all three: dev, ppe, pro)
- **Per-env CIDRs** if the defaults (`10.30/16`, `10.40/16`, `10.50/16`) collide with existing networks
- **Operator SSH source CIDRs** for ppe/pro (default `0.0.0.0/0` is open to the internet — flag this and recommend tightening for pro)
- **Node instance type** per env (defaults: `m5.large` dev, `m5.xlarge` ppe, `m5.2xlarge` pro)

### Step 2 — Copy templates into the target project

```bash
mkdir -p <project>/terraform
cp -r ${CLAUDE_PLUGIN_ROOT}/templates/terraform/. <project>/terraform/
```

(`${CLAUDE_PLUGIN_ROOT}` resolves to this skill's directory at runtime — if
that variable isn't set, use the skill's absolute path:
`~/.claude/skills/aws-k8s-kubespray-infra/`.)

### Step 3 — Replace `CHANGE_ME` placeholders

The templates contain three placeholders that **must** be replaced before
applying:

1. `key_name = "CHANGE_ME"` in **all three tfvars** → the user's real keypair name (often the same in all envs).
2. `bucket = "CHANGE_ME-tfstate"` in **all three backend hcl files** → the user's S3 state bucket.
3. (Optional) `region` in tfvars + backend hcl if not `ap-south-1`.

Do these edits programmatically so they stay in sync — don't ask the user
to do them manually.

### Step 4 — Bootstrap state backend if missing

The S3 state bucket must exist before `terraform init`. Check first:

```bash
aws s3api head-bucket --bucket <bucket> --region <region> 2>&1 || echo "NOT FOUND"
```

If missing, create with versioning + encryption (one-time per AWS account):

```bash
aws s3api create-bucket --bucket <bucket> --region <region> \
  --create-bucket-configuration LocationConstraint=<region>
aws s3api put-bucket-versioning --bucket <bucket> \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket <bucket> \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket <bucket> \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

DynamoDB is **not** needed — the backend uses S3-native conditional-write
locking (`use_lockfile = true`).

### Step 5 — Validate templates

Before plan/apply, sanity-check the config:

```bash
terraform -chdir=<project>/terraform fmt -recursive -check
terraform -chdir=<project>/terraform init -backend=false
terraform -chdir=<project>/terraform validate
```

All three must pass.

### Step 6 — Plan and apply per env

For each env the user wants:

```bash
terraform -chdir=<project>/terraform init -reconfigure -backend-config=backends/<env>.hcl
terraform -chdir=<project>/terraform plan  -var-file=<env>.tfvars -out=<env>.tfplan
terraform -chdir=<project>/terraform apply <env>.tfplan
```

After apply, the relevant outputs are `bastion_public_ip` and `node_private_ips`.

### Step 7 — Wire up SSH for the user (post-apply)

Generate an `~/.ssh/config` block per env using `ProxyJump` so the user can
`ssh <env>-node-1` without typing the bastion every time:

```
Host <env>-bastion
    HostName <bastion_public_ip>
    User ubuntu
    IdentityFile ~/.ssh/<keypair>
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new

Host <env>-node-1
    HostName <node_private_ips[0]>
    User ubuntu
    IdentityFile ~/.ssh/<keypair>
    IdentitiesOnly yes
    ProxyJump <env>-bastion
    StrictHostKeyChecking accept-new

# (repeat for node-2, node-3 …)
```

Pull `bastion_public_ip` and `node_private_ips` from `terraform output -json`.
Set `chmod 600 ~/.ssh/config`. Verify with
`ssh -o BatchMode=yes <env>-node-1 hostname`.

## Gotchas / things to call out

- **Bastion SSH open to world** when `operator_ssh_cidrs = ["0.0.0.0/0"]`.
  Fine for dev. **Always** flag this and recommend tightening before applying
  pro.
- **Single NAT-GW** is a single-AZ failure domain for outbound traffic.
  Acceptable in dev/ppe; pro defaults to `nat_gateway_count = 3`.
- **m5.large floor** in dev is tight for the full add-on stack
  (Prometheus, Kong, ArgoCD). Bump to `m5.xlarge`/`m5.2xlarge` if the platform
  footprint grows.
- **Source/dest check is disabled** on workload nodes — done deliberately so
  MetalLB L2 mode works in a later phase. Don't re-enable.
- **Pre-existing keypair**: the skill assumes the keypair already exists in
  the target region. Creating one is out of scope (operators usually upload
  their public key via `aws ec2 import-key-pair` once per account/region).
- **State bucket must be in the same region** as the resources, or set
  `region` in the backend hcl to the bucket's region explicitly.

## Reference files

- Templates: `${CLAUDE_PLUGIN_ROOT}/templates/terraform/`
- Originally distilled from a multi-tenant kubespray plan: VPC isolation
  per env, MetalLB-first LB strategy (so AWS LB resources are out of scope),
  bastion-mediated SSH, and single-root-config + per-env-tfvars deployment.

## Phases that come next (out of scope here)

This skill stops at "Terraform-applied AWS infra ready for kubespray." Follow
on with:

1. **Kubespray** — generate inventory from `node_private_ips`, set
   `loadbalancer_apiserver_localhost: true`, Calico VXLAN,
   `kube_network_plugin: calico`, run `cluster.yml` over the bastion.
2. **In-cluster prereqs** — AWS EBS CSI driver, MetalLB (L2 mode, IP pool
   carved from a free chunk of the env's VPC CIDR).
3. **GitOps** — ArgoCD App-of-Apps reconciling cert-manager (Route53 DNS-01),
   external-dns, Kong (Gateway API + Ingress), kube-prometheus-stack.
