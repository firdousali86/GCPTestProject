# GitOps Lab on GKE: Runbook

How this project deploys, where everything runs, how to reach it, and how the problems we hit were fixed.

---

## 1. At a glance

| What | Value |
|---|---|
| GitHub repo (deploys from here) | `nextimadmin/GCPTestProject`, git remote **`itc`** |
| Old/personal repo | `firdousali86/GCPTestProject`, git remote **`origin`** (no longer deploys) |
| GCP project | `testgcpproject-508711` (number `539229987082`) |
| Region | `us-central1` |
| GKE cluster | `gitops-lab-gke` (Autopilot) |
| Image registry | `us-central1-docker.pkg.dev/testgcpproject-508711/gitops-lab` |
| CI service account | `gitops-lab-github-ci@testgcpproject-508711.iam.gserviceaccount.com` |
| Workload Identity pool / provider | `gitops-lab-gh-pool` / `github` |
| App (dev) URL | **http://34.136.113.104** |
| Argo CD UI | via port-forward, see [section 4](#4-argo-cd) |

---

## 2. How a deployment works

**Argo CD watches Git, not the image registry.** CI builds the image and writes its new tag into Git. Argo CD sees the Git change and deploys it. CI never talks to the cluster.

```
 push a change under apps/backend/** or apps/frontend/**
        │
        ▼
┌─ GitHub Actions (CI) ─────────────────────────────────────────┐
│ 1. test          pytest (backend) / docker build + smoke test  │
│ 2. build-push    log in to GCP via OIDC (no stored keys)       │
│                  docker push  .../backend:<7-char commit SHA>  │
│ 3. update-manifests                                            │
│                  kustomize edit set image → new tag            │
│                  commit "deploy(dev): backend <SHA> [skip ci]" │
│                  git push → main                               │
└────────────────────────────────────────────────────────────────┘
        │   the only link between CI and the cluster is this Git commit
        ▼
┌─ Argo CD (running inside GKE) ────────────────────────────────┐
│ 4. polls GitHub every ~3 min, sees main moved                  │
│ 5. kustomize build k8s/overlays/dev → Deployment has new image │
│ 6. differs from cluster → OutOfSync → auto-sync (kubectl apply)│
└────────────────────────────────────────────────────────────────┘
        │
        ▼
 Kubernetes rolling update: new pods pull the image and pass
 their readiness checks, then the old pods are removed
```

### Key points

- **Triggers use path filters.** `backend.yml` only runs when `apps/backend/**` changes, and `frontend.yml` only when `apps/frontend/**` changes (or their workflow files change). Editing `README.md` deploys nothing.
- **`[skip ci]`** in the bot's commit stops it from starting another build. GitHub skips **every** push-triggered workflow when the newest commit in a push contains `[skip ci]`.
- **Every build gets a unique tag** (the commit SHA). Reusing `:latest` wouldn't change Git, so nothing would roll out. Unique tags also make rollback simple: `git revert` the deploy commit.
- **Login to GCP without a stored key (Workload Identity Federation).** GitHub issues a short-lived OIDC token. GCP checks that it came from `nextimadmin/GCPTestProject` and exchanges it for temporary credentials. No JSON keys are stored anywhere.

### Dev vs prod

| | Dev | Prod |
|---|---|---|
| Argo CD app | `gitops-lab-dev` | `gitops-lab-prod` |
| Overlay | `k8s/overlays/dev` | `k8s/overlays/prod` |
| Sync | **Automatic**: every commit deploys | **Manual**: two approval points |
| How to deploy | Push a code change | Run `promote-to-prod`, merge its PR, then click **Sync** in Argo CD |

```sh
gh workflow run promote-to-prod -R nextimadmin/GCPTestProject
```

Dev also has:
- `selfHeal: true`: manual `kubectl` changes are reverted to match Git.
- `prune: true`: resources deleted from Git are deleted from the cluster.

---

## 3. Accessing the app

Only the **frontend** is public (a `LoadBalancer` service). The backend is internal; nginx in the frontend forwards `/api/*` requests to it.

| URL | What you get |
|---|---|
| http://34.136.113.104/ | Web page ("GitOps lab on GKE") |
| http://34.136.113.104/api/info | Backend version, environment, and which pod answered |
| http://34.136.113.104/api/tip | Backend JSON: a tip |
| http://34.136.113.104/version.json | Frontend build version |
| http://34.136.113.104/healthz | nginx health check |

Backend directly (includes the FastAPI docs page):

```sh
kubectl -n gitops-lab-dev port-forward svc/backend 8000:8000
# http://localhost:8000/docs   /healthz   /readyz
```

The IP stays the same until the `frontend` service is deleted (for example by a teardown or a new cluster). Prod gets its own IP once it has been synced:

```sh
kubectl -n gitops-lab-prod get svc frontend
```

---

## 4. Argo CD

### Where it runs

**In GKE, in the `argocd` namespace.** It is not on your laptop. It keeps checking Git and deploying even when your laptop is off.

| Pod | What it does |
|---|---|
| `argocd-application-controller` | Checks Git every ~3 min, compares it with the cluster, applies changes |
| `argocd-repo-server` | Clones the repo and runs `kustomize build` |
| `argocd-server` | The web UI and API |
| `argocd-redis` | Cache |

### Opening the UI

The UI is internal-only by default, because whoever logs in controls the whole cluster. You reach it through a tunnel from your laptop:

```sh
kubectl -n argocd port-forward svc/argocd-server 8443:443
```

Open **https://localhost:8443**. The certificate warning is expected (self-signed).

- User: `admin`
- Password:
  ```sh
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode; echo
  ```

The port-forward only tunnels your browser to the pod in GKE; it does not run Argo CD locally. If you close the terminal, the UI tunnel closes, but deployments continue.

### App-of-apps layout

- **`root`** (`argocd/bootstrap/root-app.yaml`) is the only thing applied by hand. It watches `argocd/apps/` and creates the other Applications from it.
- **`gitops-lab-dev` / `gitops-lab-prod`** (`argocd/apps/*.yaml`) each watch their `k8s/overlays/<env>` folder.
- **`gitops-lab`** (`argocd/apps/project.yaml`) is the AppProject that limits which repo the apps may use.

### Refreshing now instead of waiting ~3 minutes

```sh
kubectl -n argocd annotate application root           argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd annotate application gitops-lab-dev argocd.argoproj.io/refresh=hard --overwrite
```

### Optional: a public URL for the UI

Quick lab option. **Change the admin password first**: the UI would be open to the whole internet.

```sh
kubectl -n argocd patch svc argocd-server -p '{"spec":{"type":"LoadBalancer"}}'
kubectl -n argocd get svc argocd-server -w     # wait for EXTERNAL-IP
```

This change isn't stored in Git, and re-running `03-install-argocd.sh` undoes it. For a real setup, use a domain, an Ingress or Gateway with a Google-managed certificate, and Identity-Aware Proxy or single sign-on through Dex.

---

## 5. Setup scripts (`scripts/`)

| Script | What it does |
|---|---|
| `00-check-prereqs.sh` | Checks that the required CLI tools are installed |
| `01-provision-infra.sh` | `terraform apply` in `infra/terraform`: network, GKE, registry, Workload Identity, service accounts |
| `02-configure-repo.sh` | Writes the registry and repo URL into the manifests and sets the GitHub Actions variables |
| `03-install-argocd.sh` | Installs Argo CD on the cluster, applies `root-app.yaml`, prints the admin password |
| `99-teardown.sh` | Destroys everything |

### GitHub Actions variables (on `nextimadmin/GCPTestProject`)

Only the repo **owner** can set these (on a personal-account repo, write access isn't enough).

```sh
R=nextimadmin/GCPTestProject
gh variable set GCP_REGION          -R $R -b "us-central1"
gh variable set GCP_PROJECT_ID      -R $R -b "testgcpproject-508711"
gh variable set GAR_REPO            -R $R -b "gitops-lab"
gh variable set WIF_PROVIDER        -R $R -b "projects/539229987082/locations/global/workloadIdentityPools/gitops-lab-gh-pool/providers/github"
gh variable set WIF_SERVICE_ACCOUNT -R $R -b "gitops-lab-github-ci@testgcpproject-508711.iam.gserviceaccount.com"
```

> On `origin`, `WIF_PROVIDER` has a stray `\r\n` at the end. Don't copy it from there.

---

## 6. Troubleshooting log (problems hit while moving to `nextimadmin`)

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | `git push itc main` → `403 Permission denied to firdousali86` | `firdousali86` only had read access to `nextimadmin/GCPTestProject` | `nextimadmin` added `firdousali86` as a collaborator with write access, and the invite was accepted. (Alternative: `https://nextimadmin@github.com/...` as the remote URL plus a personal access token for `nextimadmin`.) |
| 2 | Pushed, but **no workflow ran** | First push: its newest commit contained `[skip ci]`. Second push: only `README.md` changed, which the path filters ignore | Change something under `apps/**`, or run by hand: `gh workflow run backend -R nextimadmin/GCPTestProject` |
| 3 | `auth failed: must specify exactly one of "workload_identity_provider" or "credentials_json"` | The new repo had **no Actions variables**, so `vars.WIF_PROVIDER` was empty | The owner set the 5 variables ([section 5](#github-actions-variables-on-nextimadmingcptestproject)) |
| 4 | `invalid_target ... pool or provider is disabled or deleted` | `gitops-lab-gh-pool` **and** its provider were deleted on 2026-09-25, and were missing from Terraform state | Undelete both (possible within 30 days of deletion), import them into Terraform, point `github_repo` at the new repo, apply (commands below) |
| 5 | Terraform import of the provider: `Cannot import non-existent remote object` | The provider was deleted separately, so undeleting the pool didn't bring it back | `gcloud iam workload-identity-pools providers undelete github ...` |
| 6 | Workflows "deployed" but **nothing on the cluster** | The cluster had been recreated, so Argo CD wasn't installed. The Argo CD manifests also still pointed at `firdousali86` | Switched the `repoURL` in `argocd/**` to `nextimadmin`, pushed, ran `03-install-argocd.sh` |
| 7 | `kubectl` hung | kubectl context was set to another cluster (`tribetalk-cluster`) | `gcloud container clusters get-credentials gitops-lab-gke --region us-central1 --project testgcpproject-508711` |
| 8 | `git add`: `insufficient permission for adding an object`, then `dubious ownership` | Part of `.git` became owned by `root` (git run with `sudo`). The first fix, run from a root shell, made all of `.git` root-owned | `sudo chown -R Mac:staff .git` from a **normal** terminal. Don't use `safe.directory` |
| 9 | Pods in `ImagePullBackOff` with old tag `51a24f1` | Argo CD read the repo just before the repo-URL change landed, so it deployed the old repo's tags, whose images no longer exist | Hard refresh of `root` and `gitops-lab-dev` (section 4) |

### Restoring the Workload Identity pool (for fixes 4–5)

```sh
P=testgcpproject-508711
gcloud iam workload-identity-pools undelete gitops-lab-gh-pool --location=global --project=$P
gcloud iam workload-identity-pools providers undelete github \
  --workload-identity-pool=gitops-lab-gh-pool --location=global --project=$P

cd infra/terraform
# terraform.tfvars:  github_repo = "nextimadmin/GCPTestProject"
terraform import google_iam_workload_identity_pool.github \
  projects/$P/locations/global/workloadIdentityPools/gitops-lab-gh-pool
terraform import google_iam_workload_identity_pool_provider.github \
  projects/$P/locations/global/workloadIdentityPools/gitops-lab-gh-pool/providers/github
terraform plan    # expect: provider condition updated + github_wif binding created, no replacements
terraform apply
```

> `github_repo` accepts **one** repo, so `origin` (`firdousali86`) can no longer log in to GCP and deploy. Supporting both repos would need a Terraform change.

---

## 7. Command cheat sheet

```sh
# --- kubectl context ---
gcloud container clusters get-credentials gitops-lab-gke --region us-central1 --project testgcpproject-508711
kubectl config current-context

# --- app status ---
kubectl -n argocd get applications
kubectl -n gitops-lab-dev get pods,svc
curl http://34.136.113.104/api/info

# --- CI ---
gh run list -R nextimadmin/GCPTestProject -L 5
gh workflow run backend  -R nextimadmin/GCPTestProject
gh workflow run frontend -R nextimadmin/GCPTestProject

# --- images in the registry ---
gcloud artifacts docker images list us-central1-docker.pkg.dev/testgcpproject-508711/gitops-lab --include-tags

# --- why is a pod failing? ---
kubectl -n gitops-lab-dev describe pod <pod-name>
kubectl -n gitops-lab-dev logs <pod-name>

# --- rollback dev ---
git revert <deploy(dev) commit> && git push itc main   # Argo CD redeploys the previous tag
```
