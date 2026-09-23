#!/usr/bin/env bash
# Module 3: write registry + repo URL into the manifests, set GitHub Actions variables.
source "$(dirname "$0")/lib.sh"
need git

REGISTRY="$(tf_out registry)"
REGION="$(tf_out region)"
PROJECT="$(tf_out project_id)"
GAR_REPO="${REGISTRY##*/}"
WIF_PROVIDER="$(tf_out wif_provider)"
WIF_SA="$(tf_out wif_service_account)"
GITHUB_REPO="$(tf_out github_repo)"
REPO_URL="https://github.com/${GITHUB_REPO}.git"

info "Replacing placeholders"
echo "registry: $REGISTRY"
echo "repo url: $REPO_URL"
# sed -i.bak works on both GNU and BSD/macOS sed
for f in "$ROOT"/k8s/overlays/*/kustomization.yaml; do
  sed -i.bak "s#REGISTRY_PLACEHOLDER#${REGISTRY}#g" "$f" && rm -f "$f.bak"
done
for f in "$ROOT"/argocd/bootstrap/*.yaml "$ROOT"/argocd/apps/*.yaml; do
  sed -i.bak "s#REPO_URL_PLACEHOLDER#${REPO_URL}#g" "$f" && rm -f "$f.bak"
done

info "GitHub Actions repository variables (not secrets: nothing here is sensitive)"
if command -v gh >/dev/null; then
  gh variable set GCP_PROJECT_ID      --repo "$GITHUB_REPO" --body "$PROJECT"
  gh variable set GCP_REGION          --repo "$GITHUB_REPO" --body "$REGION"
  gh variable set GAR_REPO            --repo "$GITHUB_REPO" --body "$GAR_REPO"
  gh variable set WIF_PROVIDER        --repo "$GITHUB_REPO" --body "$WIF_PROVIDER"
  gh variable set WIF_SERVICE_ACCOUNT --repo "$GITHUB_REPO" --body "$WIF_SA"
else
  cat <<VARS
Set these in GitHub → Settings → Secrets and variables → Actions → Variables:
  GCP_PROJECT_ID      = $PROJECT
  GCP_REGION          = $REGION
  GAR_REPO            = $GAR_REPO
  WIF_PROVIDER        = $WIF_PROVIDER
  WIF_SERVICE_ACCOUNT = $WIF_SA
VARS
fi

cat <<NEXT

Next:
  1. GitHub → Settings → Actions → General → Workflow permissions:
     "Read and write permissions" and "Allow GitHub Actions to create and approve pull requests".
  2. Commit and push:
       git add -A && git commit -m "lab: configure registry and repo" && git push
  3. Run the backend and frontend workflows once (Actions tab → Run workflow)
     so both images exist before Argo CD deploys.
NEXT
