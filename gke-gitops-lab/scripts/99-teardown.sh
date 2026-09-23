#!/usr/bin/env bash
# Delete everything. Order matters: remove the LoadBalancer Services first,
# otherwise leftover forwarding rules can block VPC deletion.
source "$(dirname "$0")/lib.sh"
need kubectl; need terraform

read -r -p "This deletes the cluster, registry and all images. Type 'yes' to continue: " ok
[ "$ok" = "yes" ] || die "Aborted"

if kubectl get ns argocd >/dev/null 2>&1; then
  info "Deleting Argo CD applications (cascades to app resources)"
  kubectl -n argocd delete application root --ignore-not-found --wait=true --timeout=5m || true
  kubectl -n argocd delete application gitops-lab-dev gitops-lab-prod --ignore-not-found --wait=true --timeout=5m || true
  kubectl delete ns gitops-lab-dev gitops-lab-prod --ignore-not-found --wait=true --timeout=5m || true
fi

info "terraform destroy"
terraform -chdir="$TF_DIR" destroy

warn "The Workload Identity Pool is soft-deleted for 30 days. To rebuild within that window, change 'prefix' in terraform.tfvars."
