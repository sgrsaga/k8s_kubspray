---
name: k8s-multi-cluster-infra
description: |
  Manage multi-provider, multi-cluster Kubernetes infrastructure via Terraform.
  Use when adding a cluster, scaling nodes up or down, provisioning a new region,
  tearing down a cluster, or adding a new cloud/bare-metal provider. Triggers on:
  "add a cluster", "scale nodes", "provision AWS infra", "new region", "teardown cluster",
  "multi-cluster infra", "terraform for k8s", "add provider".
---

# Multi-Provider K8s Infrastructure

Terraform-managed Kubernetes node infrastructure across cloud providers (AWS, GCP, Azure,
DigitalOcean) and bare-metal providers (OVH, Latitude). Each provider has its own isolated
Terraform root under `terraform/<provider>/` with its own modules.

Currently live: **AWS** (networking + computing modules).
Placeholder stubs: `gcp/`, `azure/`, `digitalocean/`, `ovh/`, `latitude/`.

---

## Directory Layout

```
terraform/
├── aws/
│   ├── main.tf, variables.tf, outputs.tf, providers.tf, versions.tf
│   ├── backends/<cluster-name>.hcl    # one per cluster — S3 state key
│   ├── <cluster-name>.tfvars          # one per cluster — variable values
│   └── modules/
│       ├── networking/    # VPC, IGW, subnets, NAT GWs, route tables, SGs
│       └── computing/     # N EC2 instances (k8s nodes), Ubuntu 24.04 LTS
├── gcp/modules/           # placeholder
├── azure/modules/         # placeholder
├── digitalocean/modules/  # placeholder
├── ovh/modules/           # placeholder
└── latitude/modules/      # placeholder
```

One Terraform state per cluster. Cluster identity is `cluster_name` (e.g. `dev-ap-south-1`,
`prod-eu-west-1`). Backends and tfvars files are named to match.

---

## First-Run Setup

Replace `CHANGE_ME` in the cluster's tfvars and backend HCL before running anything:

| File | Field | Value |
|---|---|---|
| `terraform/aws/backends/<cluster>.hcl` | `bucket` | Globally-unique S3 bucket (must already exist) |
| `terraform/aws/<cluster>.tfvars` | `key_name` | Existing AWS EC2 key pair name in the target region |

The S3 bucket must be created manually (bootstrap once per AWS account):
```bash
aws s3api create-bucket \
  --bucket <your-bucket-name> \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1
aws s3api put-bucket-versioning \
  --bucket <your-bucket-name> \
  --versioning-configuration Status=Enabled
```

---

## Terraform Workflow (any cluster)

```bash
cd terraform/aws

# Initialise (first time, or after backend change)
terraform init -backend-config=backends/<cluster>.hcl -reconfigure

# Preview changes
terraform plan -var-file=<cluster>.tfvars

# Apply
terraform apply -var-file=<cluster>.tfvars

# Destroy (irreversible — confirm with user first)
terraform destroy -var-file=<cluster>.tfvars
```

Example for the default dev cluster:
```bash
cd terraform/aws
terraform init -backend-config=backends/dev-ap-south-1.hcl -reconfigure
terraform plan -var-file=dev-ap-south-1.tfvars
```

---

## How to Add a New Cluster

1. **Choose a name** — convention: `<purpose>-<region>` e.g. `prod-us-east-1`.

2. **Copy and edit the tfvars**:
   ```bash
   cp terraform/aws/dev-ap-south-1.tfvars terraform/aws/prod-us-east-1.tfvars
   # Edit: cluster_name, region, vpc_cidr, azs, subnet CIDRs, instance_type,
   #       instance_count, key_name
   ```
   Use a non-overlapping VPC CIDR for each cluster (e.g. `10.31.0.0/16` for the next one).

3. **Copy and edit the backend HCL**:
   ```bash
   cp terraform/aws/backends/dev-ap-south-1.hcl terraform/aws/backends/prod-us-east-1.hcl
   # Edit: key = "clusters/aws/prod-us-east-1/terraform.tfstate"
   #        region = "us-east-1"
   ```

4. **Initialise and apply**:
   ```bash
   cd terraform/aws
   terraform init -backend-config=backends/prod-us-east-1.hcl -reconfigure
   terraform apply -var-file=prod-us-east-1.tfvars
   ```

5. **Update kubespray inventory** — run `scripts/render-inventory.sh <cluster>` after apply.

---

## How to Scale Nodes

Change `instance_count` in the cluster's tfvars, then plan and apply:

```bash
# Edit terraform/aws/<cluster>.tfvars:
#   instance_count = 4   (was 2)

cd terraform/aws
terraform plan -var-file=<cluster>.tfvars   # shows +2 instances
terraform apply -var-file=<cluster>.tfvars
```

Scale down works the same way — Terraform destroys the highest-indexed instances first.
After scaling, re-run `scripts/render-inventory.sh` to update the kubespray inventory.

---

## AWS Networking Module

Resources per cluster:
- VPC + Internet Gateway
- 3 public subnets + 3 private subnets (one per AZ, fixed at 3)
- NAT Gateway(s): `nat_gateway_count = 1` (cheap) or `3` (HA, one per AZ)
- Public security group: SSH from `operator_ssh_cidrs`
- Private security group: intra-VPC, SSH from public SG, NodePort 30080/30443 open

## AWS Computing Module

Resources per cluster:
- N `aws_instance.node` (Ubuntu 24.04 LTS, IMDSv2-only, gp3 encrypted root)
- Nodes placed in public subnets, distributed round-robin across AZs
- Public IPs assigned — Route53 A records point to these for NodePort ingress
- `instance_count` controls N; default 2

---

## How to Add a New Provider

1. Create the provider directory:
   ```bash
   mkdir -p terraform/<provider>/modules
   ```

2. Add root config files (`main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`,
   `versions.tf`, `.gitignore`) following the AWS layout.

3. Add modules under `terraform/<provider>/modules/<module-name>/`.

4. Add per-cluster tfvars and backend HCL files.

Bare-metal providers (OVH, Latitude) follow the same pattern but use provider-specific
Terraform providers instead of `hashicorp/aws`.

---

## Key Constraints (locked — do not change without discussion)

- **No MetalLB** — L2 breaks across AZs on AWS; BGP unsupported on EC2.
- **No `Service type=LoadBalancer`** — no in-cluster LB controller. Public ingress is NodePort + Route53 multi-A.
- **S3 backend with native locking** (`use_lockfile = true`) — no DynamoDB lock table.
- **Calico VXLAN** CNI — works on AWS without src/dst-check hacks, portable to bare metal.
- **Kubespray v2.30.0 + Kubernetes 1.34.3** — bump together when upgrading.
