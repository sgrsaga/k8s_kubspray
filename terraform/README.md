# Terraform — AWS Cluster Infrastructure

Provisions the AWS network and compute resources for one Kubernetes cluster per region.
Each cluster is fully isolated: its own VPC, subnets, security groups, EC2 nodes, and S3 state key.

---

## Directory layout

```
terraform/
└── aws/
    ├── backends/
    │   ├── dev-ap-south-1.hcl       # S3 state config for ap-south-1
    │   └── dev-ap-southeast-1.hcl   # S3 state config for ap-southeast-1
    ├── modules/
    │   ├── network/                  # VPC, subnets, IGW, NAT, route tables, security groups
    │   └── compute/                  # EC2 nodes (Ubuntu 24.04 LTS, auto-resolved AMI)
    ├── main.tf                       # Wires network + compute modules
    ├── variables.tf                  # All input variables with descriptions and defaults
    ├── outputs.tf                    # Node IPs, subnet IDs, VPC ID
    ├── providers.tf                  # AWS provider (region driven by var.region)
    ├── versions.tf                   # Terraform >= 1.6, AWS ~> 5.0, S3 backend declaration
    ├── dev-ap-south-1.tfvars         # Variable values for ap-south-1
    └── dev-ap-southeast-1.tfvars     # Variable values for ap-southeast-1
```

---

## Prerequisites

| Requirement | Detail |
|---|---|
| Terraform | >= 1.6.0 |
| AWS CLI | Configured with credentials that have EC2 + VPC + IAM permissions |
| S3 bucket | `k8s-kubespray-tfstate` must exist in `ap-south-1` before first use |
| EC2 key pair | Must exist in the **target region** before apply (set as `key_name` in tfvars) |

The S3 bucket is shared across all clusters but each cluster writes to its own key:
```
clusters/aws/<cluster-name>/terraform.tfstate
```

---

## Adding a new region — step by step

### 1. Create the tfvars file

Copy an existing one and edit every value:

```bash
cp terraform/aws/dev-ap-south-1.tfvars terraform/aws/<cluster-name>.tfvars
```

```hcl
# terraform/aws/<cluster-name>.tfvars

cluster_name = "<cluster-name>"          # e.g. prod-eu-west-1
region       = "<aws-region>"            # e.g. eu-west-1
project      = "k8s-multicluster"

vpc_cidr = "10.32.0.0/16"               # must not overlap with other clusters

nat_gateway_count  = 1                   # 1 = single NAT (dev), 3 = one per AZ (HA)
operator_ssh_cidrs = ["<your-ip>/32"]    # CIDR(s) allowed to SSH to nodes

key_name       = "<keypair-name>"        # existing EC2 key pair in the target region
instance_type  = "c5a.xlarge"
instance_count = 1                       # number of k8s nodes
root_volume_gb = 100
```

> **VPC CIDR**: each cluster must use a unique, non-overlapping /16.
> Existing allocations: `10.30.0.0/16` (ap-south-1), `10.31.0.0/16` (ap-southeast-1).

### 2. Create the backend config file

```bash
cp terraform/aws/backends/dev-ap-south-1.hcl terraform/aws/backends/<cluster-name>.hcl
```

```hcl
# terraform/aws/backends/<cluster-name>.hcl

bucket       = "k8s-kubespray-tfstate"
key          = "clusters/aws/<cluster-name>/terraform.tfstate"
region       = "ap-south-1"              # bucket region — always ap-south-1
use_lockfile = true
encrypt      = true
```

Only the `key` line changes between clusters. The bucket region is always `ap-south-1` (where the bucket lives).

---

## Running Terraform

Always use `scripts/tf.sh` — never run `terraform` directly from `terraform/aws/`.
The script re-initialises Terraform with the correct S3 backend before every command,
preventing state from one cluster being applied to another.

```bash
# Preview changes
./scripts/tf.sh <cluster-name> plan

# Provision infrastructure
./scripts/tf.sh <cluster-name> apply

# Target a specific resource
./scripts/tf.sh <cluster-name> apply -target=module.network

# Tear down
./scripts/tf.sh <cluster-name> destroy
```

### Why not run terraform directly?

All clusters share the same `terraform/aws/` working directory. Terraform remembers the
last-initialised backend in `.terraform/`. Running `terraform apply -var-file=cluster-B.tfvars`
without re-initing first points Terraform at **cluster A's state**, causing it to reconcile
cluster A's live resources toward cluster B's config — destroying or corrupting cluster A.

`tf.sh` runs `terraform init -reconfigure -backend-config=backends/<cluster>.hcl` every
time, so each cluster always gets its own isolated state.

---

## What gets provisioned

### Network module
- VPC with DNS support and hostnames enabled
- 3 public subnets (one per AZ, auto-discovered from the region)
- 3 private subnets (one per AZ)
- Internet Gateway
- 1 or 3 NAT Gateways (controlled by `nat_gateway_count`)
- Public route table shared across all public subnets
- Private route table(s) routing through NAT
- **Public security group** — inbound SSH from `operator_ssh_cidrs`, all outbound
- **Private security group** — unrestricted intra-cluster traffic, all outbound

> Subnet CIDRs are auto-derived from `vpc_cidr` when not specified:
> public `/24` at offsets 0–2, private `/24` at offsets 10–12.

### Compute module
- EC2 nodes running **Ubuntu 24.04 LTS** (AMI auto-resolved per region)
- Nodes placed in public subnets with public IPs (for SSH and kubespray access)
- Nodes distributed round-robin across AZs
- Root EBS volume sized by `root_volume_gb`

---

## Key outputs

After `apply`, Terraform prints:

| Output | Use |
|---|---|
| `node_public_ips` | SSH access; set in Kubespray inventory as `ansible_host` |
| `node_private_ips` | Kubespray `ip` field (the NIC-bound address kubelet binds to) |
| `ami_id` | The resolved Ubuntu 24.04 AMI for this region |
| `vpc_id` | Reference for additional resources |
| `public_subnet_ids` | Available for load balancers or additional nodes |

Capture outputs at any time:

```bash
cd terraform/aws
terraform output -json
```

Or after a fresh init:

```bash
./scripts/tf.sh <cluster-name> output
```

---

## Next step after provisioning

Update the Kubespray inventory with the node IPs output by Terraform, then run:

```bash
./scripts/kubespray.sh <cluster-name> cluster.yml
```

See `clusters/<cluster-name>/` for inventory and group_vars configuration.
