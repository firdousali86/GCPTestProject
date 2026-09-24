#!/usr/bin/env bash
# Module 4: install Argo CD and hand the cluster over to Git.
source "$(dirname "$0")/lib.sh"
need kubectl

# Pin a release for repeatable classes, e.g. ARGOCD_VERSION=v3.1.0 ./scripts/03-install-argocd.sh
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"

grep -q REPO_URL_PLACEHOLDER "$ROOT/argocd/bootstrap/root-app.yaml" \
  && die "Run 02-configure-repo.sh and push to GitHub first."

info "Installing Argo CD ($ARGOCD_VERSION)"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# Server-side apply: the Argo CD CRDs are too large for client-side apply annotations.
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

info "Waiting for Argo CD (Autopilot provisions nodes on demand, give it a few minutes)"
kubectl -n argocd rollout status deploy/argocd-server --timeout=10m
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=10m
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=10m

info "Bootstrapping the app-of-apps"
kubectl apply -f "$ROOT/argocd/bootstrap/root-app.yaml"

PASS="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode)"
cat <<DONE

Argo CD is running.
  UI:        kubectl -n argocd port-forward svc/argocd-server 8443:443
             then open https://localhost:8443  (self-signed cert warning is expected)
  User:      admin
  Password:  $PASS

App URL (dev), once the LoadBalancer has an IP:
  kubectl -n gitops-lab-dev get svc frontend -w
DONE
