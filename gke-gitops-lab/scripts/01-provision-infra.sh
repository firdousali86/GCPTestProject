#!/usr/bin/env bash
# Module 2: create VPC, GKE Autopilot, Artifact Registry and GitHub OIDC trust.
source "$(dirname "$0")/lib.sh"
need terraform; need gcloud; need kubectl

[ -f "$TF_DIR/terraform.tfvars" ] || die "Copy infra/terraform/terraform.tfvars.example to terraform.tfvars and edit it first."

info "terraform init / apply (GKE Autopilot takes roughly 8-12 minutes)"
terraform -chdir="$TF_DIR" init -upgrade
terraform -chdir="$TF_DIR" apply

info "Fetching cluster credentials into kubeconfig"
eval "$(tf_out get_credentials_command)"
kubectl get nodes || true
echo "Autopilot may show zero nodes until the first pods are scheduled. That's expected."
