# Project: K8s on AWS via Kubespray (multi-env)

This file is loaded into every Claude Code conversation in this repo.
It encodes the project's binding decisions — Claude should follow them
without re-asking.

## What this project is

A 4-phase platform that stands up `dev` / `ppe` / `pro` Kubernetes
clusters on AWS EC2, then layers ArgoCD-managed apps on top. AWS infra
is reusable Terraform modules; cluster bootstrap is kubespray-in-Docker
(no clone). External traffic flows
`Route53 A → node public IPs : NodePort 30080/30443 → Kong → pod`
(DNS round-robin; no LB, no LB controller).

## Phases (in order)

1. **AWS infrastructure** — `terraform/`, skill `aws-infra-bootstrap`.
2. **Kubespray cluster** — `inventory/`, `playbooks/`, `scripts/`. Skill TBD.
3. **Platform addons (Kong, cert-manager `ClusterIssuer`)** — TBD.
4. **App-of-Apps (ArgoCD root + tenant apps)** — `gitops/`. TBD.

ArgoCD, cert-manager, and Longhorn are installed in Phase 2 (kubespray
addons + the `playbooks/longhorn.yml` play). The Kong proxy and the
Route53-backed cert-manager `ClusterIssuer` come in Phase 3.

## Locked decisions (do not relitigate)

- **Region default**: `ap-south-1`. Override in `*.tfvars` if needed.
- **Tenancy**: one VPC per env, one Terraform state per env, partial
  backend config switched via `-backend-config=backends/<env>.hcl`.
- **State backend**: S3 with native locking (`use_lockfile = true`).
  No DynamoDB lock table.
- **Workload nodes**: 3× EC2 (combined control-plane + worker), one per
  AZ, in **public subnets** with **public IPs**. SSH only from the
  bastion SG; NodePort 30080/30443 open to `0.0.0.0/0`.
- **Bastion**: 1× `t3.micro` in a public subnet per env. Operators reach
  nodes via `ssh -J ubuntu@<bastion> ubuntu@<node>` using
  `~/.ssh/<keypair>` (or whatever `SSH_KEY` env var points at).
- **CNI**: Calico, **VXLAN** mode (works on AWS without src/dst-check
  hacks; portable to bare metal).
- **Container runtime**: containerd.
- **CNI/Service CIDRs**: kubespray defaults
  (`10.233.64.0/18` pods, `10.233.0.0/18` services).
- **Storage**: Longhorn is the default StorageClass (3 replicas, soft
  anti-affinity). EBS CSI is **not** installed.
- **NEVER use MetalLB.** L2 mode breaks across AZs on AWS; BGP is
  unsupported on EC2. Don't propose it as a fix.
- **NEVER use Service `type=LoadBalancer`.** No in-cluster LB controller
  (no AWS LB Controller, no external CCM). Public ingress is always
  NodePort + Route53 multi-A.
- **Kubespray runs Docker-only.** Image `quay.io/kubespray/kubespray`,
  pinned in `scripts/kubespray.sh` (`KUBESPRAY_VERSION` env var). Do
  NOT git-clone the kubespray repo — only override files live here.
- **Pinned versions**: kubespray `v2.30.0`, Kubernetes `1.34.3`
  (no `v` prefix on `kube_version`). Bump together when upgrading.
- **TLS / DNS**: cert-manager + Let's Encrypt **DNS-01** against a
  Route53 zone. Configured per env via the `<your-route53-zone>`
  comment placeholder in `inventory/*/group_vars/k8s_cluster/addons.yml`.
- **GitOps**: ArgoCD App-of-Apps. Source under `gitops/`.

## Project-specific values that are placeholders

The first time someone uses this repo, they replace these `CHANGE_ME`
markers (see README → "First-run setup"):

- `terraform/backends/{dev,ppe,pro}.hcl` → `bucket` value
- `terraform/{dev,ppe,pro}.tfvars` → `key_name` value
- `inventory/{dev,ppe,pro}/group_vars/all/all.yml` → `cluster_name` host
  (`<env>.k8s.<your-domain>`)

If Claude is doing first-run setup, ask the user for these four values
together (region, state bucket name, AWS keypair name, base domain) at
the start, then template every file.

## How to drive this repo

- **Skills first.** When the user asks for a phase, prefer invoking the
  matching `.claude/skills/<phase>/` skill over hand-rolling commands.
  Phase 1 has the skill; phases 2–4 will be added.
- **`/plan` for new design work.** Phases 3 and 4 don't have skills yet
  — start them with `/plan` mode and capture the result in
  `.claude/plans/<NN>-<topic>.md`.
- **Permissions** are in `.claude/settings.json`:
  - Read-only AWS (`describe-*`), `terraform plan/init/fmt/validate`,
    `kubectl get/describe/logs`, repo reads — auto-allowed.
  - **Denied** (need explicit approval): `terraform apply`,
    `terraform destroy`, `cluster.yml` / `upgrade-cluster.yml` /
    `reset.yml` runs, `install-longhorn.sh`, AWS state-bucket / EC2 /
    Route53 mutations, `rm -rf`. Don't try to bypass these.

## Style rules for this repo

- **No emojis** in code or docs unless the user asks.
- Comments only for non-obvious "why" — don't narrate `what` the code
  does (well-named identifiers cover that).
- **Don't add LB/MetalLB/EBS-CSI/cloud-controller code** "just in case"
  — those are explicitly excluded.
- **Don't disable `source_dest_check`** on EC2 nodes; the only reason
  to do that was MetalLB, which is out.
- Keep tfvars per-env files short: `env`, network knobs, instance
  types, SSH CIDRs, keypair name. Anything truly common goes in root
  `variables.tf` defaults.

## Where things live

| Path | Purpose |
|---|---|
| `CLAUDE.md` (this file) | project rules |
| `README.md` | human onboarding (manual commands + skill pointers) |
| `.claude/settings.json` | committed permissions |
| `.claude/settings.local.json` | personal permissions (gitignored, do not commit) |
| `.claude/skills/<name>/` | project skills |
| `.claude/plans/<NN>-<topic>.md` | plan / ADR docs |
| `terraform/` | Phase 1 — AWS infra |
| `inventory/<env>/` | Phase 2 — kubespray override files |
| `playbooks/` | Phase 2/3 — custom Ansible plays |
| `scripts/` | wrappers (kubespray.sh, install-longhorn.sh, render-inventory.sh) |
| `gitops/` | Phase 4 — App-of-Apps source |
