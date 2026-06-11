# Cluster Registration

To add a new cluster to the base-addons ApplicationSet:

Install argocd utiliy

```curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

## 1. Register the cluster in ArgoCD
```bash
kubectl config get-contexts
argocd cluster add <context-name> --name <cluster-name>
```

## 2. Create the cluster directory
```
gitops/clusters/<cluster-name>/
  ├── cluster.yaml          # cluster identity (name must match ArgoCD cluster name)
  └── values/
      ├── cilium-values.yaml
      ├── cert-manager-values.yaml
      ├── externaldns-values.yaml
      └── kong-values.yaml
```

## 3. Copy the template
```bash
cp -r gitops/clusters/dev-ap-south-1 gitops/clusters/<new-cluster>
# Edit cluster.yaml (name, server URL, region)
# Edit each values/*.yaml for the new cluster's settings
```

## 4. Push to git
The base-addons ApplicationSet detects the new cluster.yaml automatically and
deploys all four addons (cilium → cert-manager → externaldns → kong) in sync-wave order.

## Result — four Applications are created automatically:
- cilium-<cluster-name>
- cert-manager-<cluster-name>
- externaldns-<cluster-name>
- kong-<cluster-name>
