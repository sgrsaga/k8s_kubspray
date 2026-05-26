# Production Kubernetes on AWS (kubespray, multi-tenant) — Plan

## Context

Stand up a production-grade, HA Kubernetes platform that can host multiple
**tenants/environments** (`dev`, `ppe`, `pro`) and is portable across **AWS
cloud VMs and bare metal** (today AWS only; bare metal joins later via the
same kubespray inventory pattern).

The shape of the AWS infrastructure is **identical for every tenant** — only
values change. Achieved with reusable Terraform **modules** (`network`,
`compute`) consumed by a single root config, parameterised by per-env files
`dev.tfvars`, `ppe.tfvars`, `pro.tfvars`.

Cluster bootstrap is via **kubespray**. There is **no load balancer** in
this design — no NLB, no MetalLB, no LB controller. Workload nodes live in
**public subnets** with public IPs, and Route53 multi-A records resolve
hostnames directly to those IPs. Clients hit `https://<host>:30443/...`;
NodePort 30080/30443 on the node SG is open to the internet.
Ingress flow: `Route53 A → node public IP : 30443 → Kong (NodePort) → pod`.
Trade-off accepted: no health-aware routing (DNS round-robin only), but
~$16/mo cheaper per env and one less moving piece. Once a cluster exists,
GitOps via **ArgoCD App-of-Apps** brings up cert-manager (already
installed), Kong with Gateway API + Ingress, and kube-prometheus-stack.

The working directory `/home/ubuntu/k8s_kubespray` is empty — this plan
creates everything from scratch.

---

## Locked decisions

- **Region**: `ap-south-1` (Mumbai), 3 AZs (`1a`, `1b`, `1c`)
- **Tenant isolation**: **one VPC per environment**, one Terraform state per
  environment, single root config switched via `-var-file=<env>.tfvars`
- **Workload nodes**: 3× EC2 (combined control-plane + worker), 1 per AZ;
  Ubuntu 24.04 LTS; instance type set per env via tfvars (default
  `m5.xlarge` dev/ppe, `m5.2xlarge` pro)
- **Bastion**: 1× small EC2 (`t3.micro`) in a public subnet per env, accessed
  via the existing AWS keypair **`mumbai`**
- **NAT**: single NAT-GW in `1a` for `dev`/`ppe`; `nat_gateway_count` toggle
  set to `3` for `pro` (one per AZ, true HA outbound)
- **Load balancing**: **none**. Workload nodes are in **public subnets**
  with **public IPs**. Route53 A records point at node public IPs;
  NodePort 30080 (HTTP) and 30443 (HTTPS) are open on the node SG to
  `0.0.0.0/0`. No NLB, no MetalLB, no LB controller. Clients resolve the
  hostname, hit a node directly on `:30443`, traffic enters Kong via
  NodePort. Failure handling = DNS round-robin (lower TTL to 60 s).
- **Workload node placement**: **public subnets** (one per AZ, same
  subnets as the bastion). They keep `private_sg_id` (intra-cluster + SSH
  from bastion + NodePort from world).
- **API server reachability**: kubespray-managed local haproxy on each node
  (`loadbalancer_apiserver_localhost: true`) — no external API LB needed
- **CNI**: Calico, VXLAN mode (works on AWS without src/dst-check changes,
  also works on bare metal)
- **Cluster bootstrap (Phase 2)**: kubespray, **Docker-only execution**
  (image `quay.io/kubespray/kubespray:v2.27.0`). **No git clone** — only
  per-env override files (`inventory.ini` + minimal `group_vars/`) live in
  this repo. One independent cluster per env.
- **Cluster name**: FQDN per env — `dev.k8s.devops-saga.click`,
  `ppe.k8s.devops-saga.click`, `pro.k8s.devops-saga.click`
- **Kubernetes version**: `v1.32.x` (latest in kubespray v2.27.0)
- **Inventory format**: static **INI** per env, AWS EC2 private IPs baked
  in, commented placeholder lines for future bare-metal joiners
- **Storage** (later phase): AWS EBS CSI on AWS nodes; `local-path` or
  longhorn on bare-metal nodes
- **TLS / DNS** (later phase): cert-manager + Let's Encrypt DNS-01 against
  Route53 zone `devops-saga.click` (env subdomains: `dev.`, `ppe.`, `pro.`)
- **GitOps** (later phase): ArgoCD App-of-Apps

---

## Architecture (per environment)

```
                                AWS  ap-south-1   (one VPC per env)
 ┌───────────────────────────────────────────────────────────────────────┐
 │  VPC <env>-vpc   CIDR per env (dev: 10.30/16, ppe: 10.40/16,          │
 │                                pro: 10.50/16)                         │
 │                                                                       │
 │   Public subnets (10.x.0/24, 10.x.1/24, 10.x.2/24) ── ALL workloads   │
 │     ├── IGW                                                           │
 │     ├── NAT-GW(s) — 1 (dev/ppe) or 3 (pro) (kept for future use)      │
 │     ├── bastion EC2 (t3.micro, key=mumbai)  ←── SSH from operator CIDR│
 │     ├── node-1 (1a)  m5.xlarge / m5.2xlarge  CP+W  (public IP)        │
 │     ├── node-2 (1b)  m5.xlarge / m5.2xlarge  CP+W  (public IP)        │
 │     └── node-3 (1c)  m5.xlarge / m5.2xlarge  CP+W  (public IP)        │
 │                                                                       │
 │   Private subnets (10.x.10/24, 10.x.11/24, 10.x.12/24) — UNUSED for   │
 │     now (reserved for future private-only resources)                  │
 │                                                                       │
 │   Public SG  : :22 from operator CIDR; egress all                     │
 │   Private SG : all-from-self, :22 from public SG (bastion-only),      │
 │                all-from-VPC-CIDR, :30080/:30443 from 0.0.0.0/0,       │
 │                egress all                                             │
 │                                                                       │
 │   Ingress flow:                                                       │
 │     internet → Route53 A (3 node public IPs, multi-value) → :30443    │
 │              → Kong (NodePort, TLS terminated here) → pod             │
 │                                                                       │
 │   API HA   = kubespray's local haproxy on each node (no AWS LB).      │
 │   No external load balancer (NLB/MetalLB explicitly excluded).        │
 └───────────────────────────────────────────────────────────────────────┘
```

---

## Repo layout

```
k8s_kubespray/
├── terraform/
│   ├── modules/
│   │   ├── network/
│   │   │   ├── main.tf            # VPC, IGW, subnets, NAT-GW(s), route tables
│   │   │   ├── sg.tf              # public-sg (bastion), private-sg (nodes + NodePort)
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf         # vpc_id, public/private subnet IDs, sg IDs
│   │   └── compute/
│   │       ├── main.tf            # bastion EC2 + workload EC2 fleet (public subnets)
│   │       ├── ami.tf             # Canonical Ubuntu 24.04 lookup
│   │       ├── variables.tf
│   │       └── outputs.tf         # bastion_public_ip, node_private_ips, node_public_ips
│   ├── main.tf                    # root: instantiates network + compute
│   ├── variables.tf               # all per-env knobs (validated)
│   ├── providers.tf               # aws provider, region from var
│   ├── versions.tf                # terraform >= 1.6, aws ~> 5.x
│   ├── outputs.tf
│   ├── backends/
│   │   ├── dev.hcl                # S3 key = envs/dev/terraform.tfstate
│   │   ├── ppe.hcl
│   │   └── pro.hcl
│   ├── dev.tfvars
│   ├── ppe.tfvars
│   └── pro.tfvars
│
├── inventory/                     # Phase 2: kubespray override files only
│   ├── dev/
│   │   ├── inventory.ini          # AWS private IPs + bastion + commented BM placeholders
│   │   ├── ansible.cfg            # host_key_checking=False, etc.
│   │   └── group_vars/
│   │       ├── all/all.yml        # cluster_name, kube_version, container_manager, LB-localhost
│   │       ├── etcd.yml           # stacked etcd, deployment_type=host
│   │       └── k8s_cluster/
│   │           ├── k8s-cluster.yml      # CNI=calico, ipvs, pod/svc CIDRs, reservations
│   │           ├── k8s-net-calico.yml   # vxlan_mode=Always, mtu
│   │           └── addons.yml           # enable argocd + cert-manager; metallb off
│   ├── ppe/                       # same shape, different IPs
│   └── pro/
│
├── scripts/
│   ├── kubespray.sh               # `./scripts/kubespray.sh <env> <playbook>` wrapper
│   └── render-inventory.sh        # generate inventory.ini from `terraform output -json`
│
└── gitops/                        # later: ArgoCD App-of-Apps source
```

Backend init per env:
```
terraform -chdir=terraform init -backend-config=backends/dev.hcl
terraform -chdir=terraform apply -var-file=dev.tfvars
```

---

## Phase 1 — Terraform: modules + per-env tfvars

### Module: `network`

Inputs (subset; full list in `modules/network/variables.tf`):

| Variable | Type | Notes |
|---|---|---|
| `env` | string | `dev` \| `ppe` \| `pro`. Used as name prefix and tag. |
| `vpc_cidr` | string | e.g. `10.30.0.0/16`. |
| `azs` | list(string) | e.g. `["ap-south-1a","ap-south-1b","ap-south-1c"]`. |
| `public_subnet_cidrs` | list(string) | length must equal `azs`. |
| `private_subnet_cidrs` | list(string) | length must equal `azs`. |
| `nat_gateway_count` | number | `1` for dev/ppe, `3` for pro. |
| `operator_ssh_cidrs` | list(string) | source CIDRs allowed on bastion :22. |
| `tags` | map(string) | merged into every resource. |

Resources created:
- `aws_vpc` with DNS support/hostnames on, tagged `{Name="${env}-vpc", env=...}`.
- `aws_internet_gateway` attached to the VPC.
- 3× `aws_subnet` public (map_public_ip_on_launch=true), 3× `aws_subnet`
  private — keyed by AZ, named `${env}-public-1a` / `${env}-private-1a`, etc.
- `aws_eip` + `aws_nat_gateway` × `nat_gateway_count`. Route table layout:
  - One public RT, default route → IGW, associated with all public subnets.
  - **If `nat_gateway_count == 1`**: one private RT, default route → the
    single NAT-GW, associated with all 3 private subnets.
  - **If `nat_gateway_count == 3`**: three private RTs, each default route
    → its AZ's NAT-GW, associated with that AZ's private subnet.
- `aws_security_group "public"`: ingress 22 from `operator_ssh_cidrs`, egress
  all. (Bastion attaches to this.)
- `aws_security_group "private"`: ingress 22 from `public` SG (bastion-only),
  ingress all from `vpc_cidr` (so kubespray's many ports work intra-VPC
  without listing each), ingress all from self (intra-SG), **ingress
  30080/30443 (NodePort) from `0.0.0.0/0`** (Route53-resolved clients hit
  the node directly; with no NLB the node SG is the only filter — client
  IP is preserved), egress all.

Outputs: `vpc_id`, `vpc_cidr`, `public_subnet_ids[]`, `private_subnet_ids[]`,
`public_sg_id`, `private_sg_id`, `azs[]`.

### Module: `compute`

Inputs:

| Variable | Type | Notes |
|---|---|---|
| `env` | string | propagated from root. |
| `key_name` | string | `mumbai` (the existing AWS keypair). |
| `bastion_instance_type` | string | default `t3.micro`. |
| `node_instance_type` | string | per env (`m5.xlarge` dev/ppe; `m5.2xlarge` pro). |
| `node_count` | number | default `3`. |
| `node_root_volume_gb` | number | default `100`. |
| `public_subnet_ids` | list(string) | from network module output. |
| `private_subnet_ids` | list(string) | from network module output. |
| `public_sg_id` | string | for bastion. |
| `private_sg_id` | string | for nodes. |
| `tags` | map(string) | merged. |

Resources:
- `data.aws_ami` Ubuntu 24.04 LTS (Canonical owner `099720109477`,
  `ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*`).
- `aws_instance "bastion"`: 1 instance, `t3.micro`, in
  `public_subnet_ids[0]`, `public_sg_id`, `key_name=mumbai`,
  `associate_public_ip_address=true`, IMDSv2 required, EBS gp3 20 GB
  encrypted, tagged `{Name="${env}-bastion"}`.
- `aws_instance "node"` × `node_count`: spread across **`public_subnet_ids`**
  via `count.index % length(public_subnet_ids)` (so node-1 → AZ 1a,
  node-2 → 1b, node-3 → 1c). `private_sg_id`, `key_name=mumbai`,
  `associate_public_ip_address=true`, IMDSv2 required, root volume
  `node_root_volume_gb` gp3 encrypted, tagged
  `{Name="${env}-node-${count.index+1}"}`.

Outputs: `bastion_public_ip`, `bastion_instance_id`, `node_private_ips[]`,
`node_public_ips[]`, `node_instance_ids[]`.

### Route53 records (manual, post-apply)

Outside Terraform's scope here. After `terraform apply` returns
`node_public_ips`, point an A record at all three:

```bash
HOST=k8s.dev.devops-saga.click          # apex for the env
ZONE_ID=Z123EXAMPLE                     # devops-saga.click hosted zone

terraform -chdir=terraform output -json node_public_ips \
  | jq -r '.[]' \
  | xargs -I{} echo '"{}"' \
  | jq -s --arg name "$HOST" '{
      Comment: "k8s nodes",
      Changes: [{
        Action: "UPSERT",
        ResourceRecordSet: {
          Name: $name, Type: "A", TTL: 60,
          MultiValueAnswer: true, SetIdentifier: ($name+"-multi"),
          ResourceRecords: ([.[] | {Value: .}])
        }
      }]
    }' \
  | aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" \
      --change-batch file:///dev/stdin
```

Lower TTL to 60 s so a dead-node IP rolls out within a minute.
A future iteration can fold this into a Terraform `route53` module or
let external-dns manage per-app hostnames dynamically.


Composes the two modules:
```hcl
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
  env                  = var.env
  key_name             = var.key_name
  bastion_instance_type = var.bastion_instance_type
  node_instance_type    = var.node_instance_type
  node_count            = var.node_count
  public_subnet_ids     = module.network.public_subnet_ids
  private_subnet_ids    = module.network.private_subnet_ids
  public_sg_id          = module.network.public_sg_id
  private_sg_id         = module.network.private_sg_id
  tags                  = local.tags
}

```

### Per-env tfvars

`dev.tfvars`:
```hcl
env                   = "dev"
vpc_cidr              = "10.30.0.0/16"
azs                   = ["ap-south-1a","ap-south-1b","ap-south-1c"]
public_subnet_cidrs   = ["10.30.0.0/24","10.30.1.0/24","10.30.2.0/24"]
private_subnet_cidrs  = ["10.30.10.0/24","10.30.11.0/24","10.30.12.0/24"]
nat_gateway_count     = 1
operator_ssh_cidrs    = ["0.0.0.0/0"]   # tighten before pro
key_name              = "mumbai"
bastion_instance_type = "t3.micro"
node_instance_type    = "m5.xlarge"
node_count            = 3
```

`ppe.tfvars` — same shape, `vpc_cidr = "10.40.0.0/16"`, subnets shifted,
`nat_gateway_count = 1`.

`pro.tfvars` — `vpc_cidr = "10.50.0.0/16"`, `nat_gateway_count = 3`,
`node_instance_type = "m5.2xlarge"`, `operator_ssh_cidrs` restricted to
office/CI CIDRs.

### State backend

S3 backend + DynamoDB lock, **one state key per env** via partial backend:
```hcl
# backends/dev.hcl
bucket         = "k8s-kubespray-tfstate"
key            = "envs/dev/terraform.tfstate"
region         = "ap-south-1"
dynamodb_table = "k8s-kubespray-tflock"
encrypt        = true
```
The S3 bucket + DynamoDB table are created out of band by a one-shot
bootstrap (small separate config or AWS CLI commands — not blocking).

### Apply workflow

```
terraform -chdir=terraform fmt -check
terraform -chdir=terraform init   -backend-config=backends/dev.hcl
terraform -chdir=terraform plan   -var-file=dev.tfvars  -out=dev.tfplan
terraform -chdir=terraform apply  dev.tfplan
```
Re-init with the `ppe`/`pro` backend to switch envs (or use Terraform
workspaces — backend-file approach is simpler and more explicit).

### Phase 1 verification

1. `terraform plan -var-file=dev.tfvars` is clean and creates only the
   resources listed above.
2. After apply: `aws ec2 describe-instances --filters "tag:env,Values=dev"`
   shows 1 bastion + 3 nodes, all `running`. The 3 nodes each have a
   public IP, all in the public subnets.
3. `ssh -i ~/.ssh/mumbai ubuntu@<bastion_public_ip>` succeeds.
4. `terraform output -json node_public_ips` returns 3 IPs; `curl --max-time 5
   http://<each>:30080` returns "connection refused" / TCP RST (expected —
   nothing listens on the NodePort until Phase 5 when Kong is installed).
5. SSH to a node via its **public IP** is **denied** (no rule for that —
   SSH must come through the bastion only); ProxyJump via bastion still
   works: `ssh -i ~/.ssh/mumbai -J ubuntu@<bastion> ubuntu@<node>`.
6. `terraform destroy -var-file=dev.tfvars` cleans up with no leftovers.
7. Re-init for `ppe`, apply, verify the same — confirms parity across envs.

---

## Phase 2 — Kubespray (per-env clusters, Docker-only)

Each environment gets its **own independent cluster**. We do **not** clone
the kubespray repo — every kubespray playbook is shipped inside the official
Docker image. We only commit per-env *override files* and run them via
`docker run`. Reference: <https://kubespray.io/#/>.

### What lives in this repo

For each env, a small tree under `inventory/<env>/`:

- **`inventory.ini`** — static INI inventory: AWS EC2 private IPs from the
  Phase 1 Terraform outputs, plus commented `# bm-node-N ansible_host=...`
  placeholders so adding a real bare-metal joiner later is a 1-line edit.
- **`ansible.cfg`** — sets `host_key_checking = False` and the inventory
  path so the docker invocation stays clean.
- **`group_vars/`** — only the variables we override; everything else uses
  kubespray's defaults baked into the image.

### Inventory: `inventory/dev/inventory.ini` (example)

```ini
# All hosts the playbook may touch.
[all]
node-1 ansible_host=10.30.10.11  ip=10.30.10.11  etcd_member_name=etcd1
node-2 ansible_host=10.30.11.138 ip=10.30.11.138 etcd_member_name=etcd2
node-3 ansible_host=10.30.12.164 ip=10.30.12.164 etcd_member_name=etcd3
# Future bare-metal joiners — uncomment and re-run scale.yml when ready:
# bm-node-1 ansible_host=192.168.10.10 ip=192.168.10.10
# bm-node-2 ansible_host=192.168.10.11 ip=192.168.10.11

# Kubespray reads this and configures ProxyJump automatically.
[bastion]
bastion ansible_host=3.110.162.33 ansible_user=ubuntu

[kube_control_plane]
node-1
node-2
node-3

[etcd]
node-1
node-2
node-3

[kube_node]
node-1
node-2
node-3
# bm-node-1
# bm-node-2

[k8s_cluster:children]
kube_control_plane
kube_node
```

`ppe` and `pro` are identical in shape — only the IPs differ.

### Override files (`inventory/<env>/group_vars/`)

Only the keys we change from defaults. Everything not listed inherits kubespray defaults.

- `all/all.yml`
  - `cluster_name: "<env>.k8s.devops-saga.click"`
  - `container_manager: containerd`
  - `kube_version: v1.32.x`
  - `loadbalancer_apiserver_localhost: true` *(API HA via per-node haproxy)*
  - `loadbalancer_apiserver_port: 6443`
  - `ansible_user: ubuntu`
  - `ansible_ssh_private_key_file: /root/.ssh/id_rsa` *(path inside the kubespray container)*
- `etcd.yml`
  - `etcd_deployment_type: host` *(stacked etcd, on the same nodes)*
  - `etcd_metrics: basic`
- `k8s_cluster/k8s-cluster.yml`
  - `kube_network_plugin: calico`
  - `kube_proxy_mode: ipvs`
  - `kube_pods_subnet: 10.233.64.0/18` *(kubespray default; safe vs VPC CIDRs)*
  - `kube_service_addresses: 10.233.0.0/18`
  - `kube_reserved: { cpu: 300m, memory: 512Mi }`
  - `system_reserved: { cpu: 200m, memory: 512Mi }`
- `k8s_cluster/k8s-net-calico.yml`
  - `calico_vxlan_mode: Always`
  - `calico_ipip_mode: Never`
  - `calico_mtu: 1450`
- `k8s_cluster/addons.yml`
  - `helm_enabled: true`
  - `metrics_server_enabled: true`
  - `argocd_enabled: true` *(kubespray installs ArgoCD into `argocd` ns)*
  - `cert_manager_enabled: true` *(kubespray installs cert-manager + CRDs)*
  - `metallb_enabled: false` *(removed — does not work cleanly on EC2)*
  - `ingress_nginx_enabled: false` *(Kong via Helm in Phase 5)*

### Running kubespray (one command per env)

A single reproducible `docker run` works for any kubespray playbook
(`cluster.yml`, `scale.yml`, `upgrade-cluster.yml`, `reset.yml`).
Wrapped in `scripts/kubespray.sh`:

```bash
# scripts/kubespray.sh
ENV="${1:?env required (dev|ppe|pro)}"
PLAYBOOK="${2:-cluster.yml}"
KSPV="v2.27.0"

docker run --rm -it \
  -v "$(pwd)/inventory/${ENV}:/inventory" \
  -v "${HOME}/.ssh/mumbai:/root/.ssh/id_rsa:ro" \
  -e ANSIBLE_HOST_KEY_CHECKING=False \
  -e ANSIBLE_CONFIG=/inventory/ansible.cfg \
  "quay.io/kubespray/kubespray:${KSPV}" \
  ansible-playbook -i /inventory/inventory.ini \
    --become --become-user=root \
    "${PLAYBOOK}"
```

Day-to-day:

| Operation | Command |
|---|---|
| First-time install | `./scripts/kubespray.sh dev cluster.yml` |
| Add a node (e.g. new BM) | edit `inventory.ini`, then `./scripts/kubespray.sh dev scale.yml` |
| Patch / minor upgrade | `./scripts/kubespray.sh dev upgrade-cluster.yml` (after bumping `kube_version`) |
| Tear down (destructive) | `./scripts/kubespray.sh dev reset.yml` |

### Inventory generation from Terraform

`scripts/render-inventory.sh <env>` reads `terraform output -json` for that
env's state and rewrites the `[all]` block of `inventory/<env>/inventory.ini`
with the current bastion + node IPs. Run once after `terraform apply` (and
again whenever Phase 1 is re-applied with changed IPs). Bare-metal lines are
preserved untouched — only AWS-derived hosts are regenerated.

### Fetching kubeconfig after `cluster.yml`

Kubespray writes `/etc/kubernetes/admin.conf` on each control-plane node.
Pull it once, point it at the bastion-routed API:

```bash
ssh dev-node-1 'sudo cat /etc/kubernetes/admin.conf' \
  | sed 's|server: https://.*:6443|server: https://127.0.0.1:6443|' \
  > ~/.kube/config-dev
# Then run a local SSH port-forward via the bastion:
ssh -N -L 6443:10.30.10.11:6443 k8s-dev-bastion &
KUBECONFIG=~/.kube/config-dev kubectl get nodes
```

(For long-running operator use, keep the SSH tunnel up via `ssh -f -N`. The
API server is reached only through the bastion — there is no public LB
fronting `:6443`.)

### Phase 2 verification

1. `./scripts/kubespray.sh dev cluster.yml` exits 0.
2. `kubectl --kubeconfig ~/.kube/config-dev get nodes -o wide` shows 3×
   `Ready`, roles `control-plane,worker`, version `v1.32.x`.
3. `kubectl get pods -A` — all `Running`/`Completed`. Calico pods present
   on every node.
4. **HA**: `kubectl drain dev-node-1 --ignore-daemonsets --delete-emptydir-data`;
   API stays responsive (haproxy on the other 2 nodes serves), then
   `kubectl uncordon dev-node-1` brings it back.
5. **Quorum**: stop one EC2 from the AWS console; etcd stays healthy
   (2/3 quorum); start it, watch it rejoin.
6. **Cross-env parity**: repeat the run for `ppe` and `pro`. Three fully
   independent clusters online, each reachable through its own bastion.

---

## Phases 3–5 (overview, scoped per env)

These are unchanged from the prior plan in spirit, but each step is run **per
env** against that env's infrastructure. Brief recap so the document stays
self-contained:

- **Phase 3 — In-cluster prerequisites**: install **Longhorn** as the default
  StorageClass (3 replicas, soft anti-affinity) via the
  `playbooks/longhorn.yml` Ansible play (run through the kubespray docker
  image — installs `open-iscsi`/`nfs-common` on each node, then helms in
  `longhorn/longhorn`). No LB controller; no NLB.
- **Phase 4 — ArgoCD bootstrap**: ArgoCD itself is installed by kubespray
  (Phase 2). Apply the App-of-Apps root `Application` pointing at a per-env
  directory in the GitOps repo so subsequent platform apps reconcile from
  Git. Initial admin password rotated.
- **Phase 5 — Platform apps**: cert-manager `ClusterIssuer` (Route53 DNS-01
  against `devops-saga.click`); Kong (Gateway API + Ingress) installed as
  **`Service type=NodePort` with `nodePort: 30080/30443`** so traffic from
  Route53 → node public IP → NodePort lands on the proxy; Route53 multi-A
  records (TTL 60) point apex/wildcard hostnames at the 3 node public
  IPs (managed manually or by external-dns); kube-prometheus-stack.

---

## Risks / callouts

1. **Bastion SSH open to the world** in the dev/ppe defaults
   (`operator_ssh_cidrs = ["0.0.0.0/0"]`). Tighten to office/CI CIDRs in
   `pro.tfvars` before that env carries any data; consider doing the same
   for ppe.
2. **No load balancer; nodes carry public IPs and serve traffic directly.**
   Trade-offs accepted:
   - **DNS round-robin only.** A dead node still serves ~1/3 of clients
     until DNS TTL expires — keep TTL ≤ 60 s.
   - **Non-standard ports in URLs.** Clients use `:30443`/`:30080`.
     Browsers and curl handle this fine; some upstream CDNs/firewalls may
     not.
   - **Each node is internet-reachable.** Defense rests on the node SG
     (SSH bastion-only, only 30080/30443 from world) plus k8s RBAC. Patch
     the OS, monitor `auth.log`, consider `fail2ban`.
   - **No connection draining on node loss.** A node going down severs
     established TCP sessions to clients still resolving its IP.
3. **Single NAT gateway** for dev/ppe is a single-AZ failure domain for
   outbound traffic. `pro` uses 3 NAT-GWs via `nat_gateway_count=3` toggle.
4. **m5.xlarge floor** (dev/ppe) is tight for the full add-on stack
   (Prometheus, Kong, ArgoCD). Watch memory; be ready to bump dev/ppe to
   `m5.2xlarge` if the platform footprint grows.
5. **Combined control-plane + worker** means a memory-hungry workload can
   pressure etcd/api-server. Set `kube_reserved` / `system_reserved` in
   kubespray group_vars in Phase 2 and resource limits on tenant workloads.
6. **Pod-level AWS perms** (Phase 5 onward): without IRSA on a self-managed
   cluster, pods inherit the node IAM role. Acceptable for a single-team
   platform cluster; revisit if multi-tenant inside a single cluster is on
   the roadmap.
7. **Bare-metal joiners** will need their own IP allocation and routing back
   to the AWS VPC (VPN/Direct Connect). Public traffic to BM-only services
   would need its own ingress path (BM public IPs in Route53, or a CDN/LB
   in front). Out of scope here but kubespray + Calico VXLAN are portable
   across both fleets.
