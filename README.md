# K8s on AWS via Kubespray (multi-env)

Production-grade Kubernetes platform spanning multiple environments
(`dev` / `ppe` / `pro`) — and portable to bare metal. AWS infrastructure is
reusable Terraform modules; cluster bootstrap is kubespray-in-Docker (no
clone); storage is Longhorn; external traffic flows
`Route53 A → node public IPs : NodePort 30080/30443` (DNS round-robin, no LB).

This repo is **Claude-Code-native**: project-level skills under `.claude/`
encode the multi-step workflows for each phase. Run Claude Code in this
directory and invoke the skills, or follow the manual commands below.

## Phases

| # | Phase | Skill / how to run |
|---|---|---|
| 1 | AWS infrastructure (Terraform) | `.claude/skills/aws-infra-bootstrap/` |
| 2 | Kubernetes cluster (Kubespray) | `.claude/skills/kubespray-cluster-bootstrap/` |
| 3 | Platform addons (cert-manager, Kong) | `.claude/skills/install-platform-addons/` *(TBD)* |
| 4 | App-of-Apps GitOps (ArgoCD) | `.claude/skills/argocd-app-of-apps/` *(TBD)* |

ArgoCD, cert-manager, and Longhorn ship with Phase 2; Kong and the
ClusterIssuer come in Phase 3.

## Project conventions

See [`CLAUDE.md`](./CLAUDE.md) for the binding rules (region, kubespray /
k8s versions, no MetalLB, etc.).

## Repository layout

```
.
├── CLAUDE.md                  project conventions (loaded by Claude Code)
├── .claude/
│   ├── settings.json          permissions / env / hooks
│   ├── skills/                project-level skills (one per phase)
│   └── plans/                 design plans / ADRs
├── terraform/                 Phase 1 — AWS infrastructure
│   ├── modules/{network,compute}/
│   ├── backends/{dev,ppe,pro}.hcl       # state bucket + key per env
│   ├── {dev,ppe,pro}.tfvars             # per-env values
│   └── {versions,providers,variables,main,outputs}.tf
├── inventory/                 Phase 2 — kubespray override files (per env)
│   ├── {dev,ppe,pro}/
│   │   ├── inventory.ini      # AWS private IPs (rendered post-apply) + BM placeholders
│   │   ├── ansible.cfg
│   │   └── group_vars/{all,etcd,k8s_cluster}/...
├── playbooks/
│   └── longhorn.yml           Longhorn install (prereqs + helm)
├── scripts/
│   ├── kubespray.sh           docker wrapper for any kubespray (or /playbooks/) playbook
│   ├── install-longhorn.sh    wraps kubespray.sh against playbooks/longhorn.yml
│   └── render-inventory.sh    syncs inventory.ini IPs from `terraform output -json`
└── gitops/                    Phase 4 — App-of-Apps source (ArgoCD reconciles this)
```

## Prerequisites

- `terraform >= 1.6`
- `docker`
- `aws` CLI v2, configured for the target region
- `jq`
- An AWS keypair already created in the target region; the matching private
  key on your laptop at `~/.ssh/<keyname>` (mode 600). Set the `SSH_KEY`
  env var when running `scripts/*.sh` if it isn't `~/.ssh/id_rsa`.
- An S3 bucket for Terraform state (one-time bootstrap below).

## First-run setup (per project)

The values you'll be replacing in the templates the **first time** you use
this repo:

| Placeholder | Where | What it becomes |
|---|---|---|
| `CHANGE_ME-tfstate` | `terraform/backends/*.hcl` | Your globally-unique S3 state bucket name |
| `CHANGE_ME` (key_name) | `terraform/{dev,ppe,pro}.tfvars` | Your existing AWS keypair name in the target region |
| `<env>.k8s.CHANGE_ME` | `inventory/*/group_vars/all/all.yml` (`cluster_name`) | `<env>.k8s.<your-domain>` |
| `<your-route53-zone>` | `inventory/*/group_vars/k8s_cluster/addons.yml` (comments) | The Route53 zone you'll use for cert-manager DNS-01 |

Region defaults to `ap-south-1` in the tfvars; change if needed.

## One-time: Terraform state backend

```bash
BUCKET=<your-state-bucket-name>
REGION=ap-south-1                 # or your region

aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

State locking uses S3 native locks (`use_lockfile = true`), so no DynamoDB
table is needed.

## Running a phase manually

If you'd rather not invoke the skills, the manual sequence per env is:

```bash
ENV=dev

# Phase 1 — AWS infra
terraform -chdir=terraform init -reconfigure -backend-config=backends/${ENV}.hcl
terraform -chdir=terraform plan  -var-file=${ENV}.tfvars -out=${ENV}.tfplan
terraform -chdir=terraform apply ${ENV}.tfplan

# Sync inventory IPs from Terraform outputs
./scripts/render-inventory.sh ${ENV}

# Phase 2 — Cluster + built-in addons (~25 min)
SSH_KEY=~/.ssh/<your-keypair> ./scripts/kubespray.sh ${ENV} cluster.yml

# Storage (Longhorn — runs after cluster.yml)
SSH_KEY=~/.ssh/<your-keypair> ./scripts/install-longhorn.sh ${ENV}

# Fetch kubeconfig (post-cluster.yml)
BASTION=$(terraform -chdir=terraform output -raw bastion_public_ip)
NODE=$(terraform -chdir=terraform output -json node_private_ips | jq -r '.[0]')
ssh -i ~/.ssh/<your-keypair> -J ubuntu@${BASTION} ubuntu@${NODE} \
    sudo cat /etc/kubernetes/admin.conf \
  | sed "s|https://.*:6443|https://127.0.0.1:6443|" \
  > ~/.kube/config-${ENV}

# Background API tunnel (clients use https://127.0.0.1:6443 via the tunnel)
ssh -i ~/.ssh/<your-keypair> -f -N \
  -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
  -L 6443:${NODE}:6443 ubuntu@${BASTION}

KUBECONFIG=~/.kube/config-${ENV} kubectl get nodes -o wide
```

## Day-2 operations

| Operation | Command |
|---|---|
| Add a node (e.g. BM joiner) | edit `inventory/<env>/inventory.ini`, then `./scripts/kubespray.sh <env> scale.yml` |
| Patch / minor upgrade | bump `kube_version` in `inventory/<env>/group_vars/all/all.yml`, then `./scripts/kubespray.sh <env> upgrade-cluster.yml` |
| Cluster reset (destructive) | `./scripts/kubespray.sh <env> reset.yml` |
| Tear down infra | `terraform -chdir=terraform destroy -var-file=<env>.tfvars` |

## Verification (after Phase 2)

```bash
export KUBECONFIG=~/.kube/config-<env>

kubectl get nodes -o wide                    # 3 Ready, control-plane,worker
kubectl get pods -A                          # all Running/Completed
kubectl get sc                               # `longhorn (default)`
kubectl get pods -n longhorn-system          # all Running
kubectl get pods -n argocd
kubectl get pods -n cert-manager

# Node public IPs (these become Route53 A records)
terraform -chdir=terraform output -json node_public_ips | jq -r '.[]'

# ArgoCD initial admin password (rotate immediately)
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo
```

## Risks / gotchas

1. **`pro.tfvars` ships with `operator_ssh_cidrs = ["0.0.0.0/0"]`** as a
   placeholder. Tighten to office/CI/VPN CIDRs **before** the first
   `terraform apply -var-file=pro.tfvars`.
2. **No load balancer; nodes carry public IPs and serve traffic directly.**
   DNS round-robin only — keep TTL ≤ 60 s. Clients use non-standard ports
   in URLs (`:30443`/`:30080`).
3. **Single NAT-GW** for dev/ppe is a single-AZ failure domain for
   outbound traffic. Pro uses 3 NAT-GWs (one per AZ).
4. **kubespray v2.30.0 + kubernetes 1.34.3** are pinned. Bump together
   in `inventory/<env>/group_vars/all/all.yml` (`kube_version`) and the
   `KUBESPRAY_VERSION` default in `scripts/kubespray.sh`.
5. **Longhorn** is the default StorageClass. Anything assuming
   `local-path` or EBS-CSI will need explicit `storageClassName`.
6. **ArgoCD's initial admin password** is auto-generated and stored in the
   `argocd-initial-admin-secret`. Rotate it the first time you log in.
7. **cert-manager has no `ClusterIssuer` yet** — installed but won't mint
   certificates until Phase 3 applies a `ClusterIssuer` (Route53 DNS-01).

## References

- Kubespray docs: <https://kubespray.io/#/>
- Kubespray addons (release-2.30):
  <https://github.com/kubernetes-sigs/kubespray/blob/release-2.30/inventory/sample/group_vars/k8s_cluster/addons.yml>
- Longhorn: <https://longhorn.io/docs/>
- cert-manager: <https://cert-manager.io/docs/>
- ArgoCD: <https://argo-cd.readthedocs.io/>
- Route53 multi-value answer routing:
  <https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy-multivalue.html>
