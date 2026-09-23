#!/usr/bin/env bash
# Module 0: confirm tools and gcloud login.
source "$(dirname "$0")/lib.sh"

for t in gcloud terraform kubectl git docker; do need "$t"; echo "ok  $t"; done
command -v gh >/dev/null && echo "ok  gh (optional, used to set repo variables)" || warn "gh not found: you'll set GitHub variables by hand"
command -v argocd >/dev/null && echo "ok  argocd CLI (optional)" || warn "argocd CLI not found: the web UI is enough"

gcloud components list --only-local-state --format="value(id)" 2>/dev/null | grep -q gke-gcloud-auth-plugin \
  || command -v gke-gcloud-auth-plugin >/dev/null \
  || warn "Install the GKE auth plugin: gcloud components install gke-gcloud-auth-plugin"

info "Active gcloud account and project"
gcloud config list --format="table(core.account,core.project)"
gcloud auth application-default print-access-token >/dev/null 2>&1 \
  || warn "Terraform needs ADC: run  gcloud auth application-default login"
