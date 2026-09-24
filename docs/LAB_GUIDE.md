# Lab Guide: GitOps on GKE

Each module ends with a **checkpoint**. Don't move on until it passes. Times are for a trainee working alone; pairs are usually faster.

---

## Module 0 · Orientation and tooling (20 min)

**Goal:** a working `gcloud` and a mental map from AWS/Azure to GCP.

1. Fork or push this repo to your own GitHub account.
2. Log in twice. The first login is for you, the second is for Terraform (Application Default Credentials):
   ```bash
   gcloud auth login
   gcloud auth application-default login
   gcloud config set project YOUR_PROJECT_ID
   gcloud components install gke-gcloud-auth-plugin   # if missing
   ```
3. Run `./scripts/00-check-prereqs.sh`.

Things to notice if you come from AWS or Azure: a **project** is your account/subscription boundary; APIs are enabled per project; `gcloud config configurations create client-x` is how you keep multiple customers apart, like AWS CLI profiles.

**Checkpoint:** `gcloud config list` shows your account and project, and the prereq script reports no missing tools.

---

## Module 1 · Run the app locally (15 min)

**Goal:** understand what we're deploying before we deploy it.

```bash
docker compose up --build
```
Open http://localhost:8080. The coloured strip shows one block per request, coloured by the backend instance that answered. Locally there is only one, so it's one colour. On GKE you'll see several.

Read `apps/frontend/nginx.conf`: the frontend reaches the backend by the name `backend`. In Kubernetes that name is a Service.

**Checkpoint:** the page shows `Environment: local` and a GCP tip.

---

## Module 2 · Provision GCP infrastructure with Terraform (30 min, mostly waiting)

**Goal:** VPC, GKE Autopilot, Artifact Registry and keyless GitHub trust.

```bash
cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars
# edit project_id and github_repo (owner/name, exactly as on GitHub)
./scripts/01-provision-infra.sh
```

While it runs, read `infra/terraform/main.tf` top to bottom and answer these:

1. Why does the subnet have two secondary ranges? (Pods and Services get VPC-native IPs.)
2. What does `attribute_condition` on the identity pool provider stop? (Any other GitHub repo using your pool.)
3. Which identity pulls images for the pods, and which role lets it? (The `gke_nodes` service account with `artifactregistry.reader`.)
4. What's the Azure equivalent of `google_service_account_iam_member.github_wif`? (A federated credential on an app registration.)

**Checkpoint:**
```bash
kubectl cluster-info
gcloud artifacts repositories list --location=REGION
```

---

## Module 3 · Continuous integration with GitHub Actions (30 min)

**Goal:** every merge to `main` produces a tested image in Artifact Registry and a Git commit that records it.

1. Run `./scripts/02-configure-repo.sh`. It writes the registry path and your repo URL into the manifests and sets five repository **variables** (not secrets, because nothing is secret with keyless auth).
2. In GitHub → Settings → Actions → General → Workflow permissions: select **Read and write permissions** and tick **Allow GitHub Actions to create and approve pull requests**.
3. Commit and push. Then Actions → **backend** → Run workflow, and the same for **frontend**.

Read `.github/workflows/_build-push.yml` while it runs:

- `id-token: write` is what lets the job ask GitHub for an OIDC token.
- `google-github-actions/auth` swaps that token for short-lived GCP credentials.
- The second job doesn't deploy anything. It runs `kustomize edit set image` and **commits** the new tag to `k8s/overlays/dev/kustomization.yaml`.
- The `concurrency` group stops the two pipelines from racing each other on `git push`.

**Checkpoint:**
```bash
gcloud artifacts docker images list REGION-docker.pkg.dev/PROJECT/gitops-lab
git pull && git log --oneline -3     # you should see "deploy(dev): ..." commits from github-actions[bot]
```

---

## Module 4 · GitOps with Argo CD (30 min)

**Goal:** the cluster pulls its desired state from Git.

```bash
./scripts/03-install-argocd.sh
kubectl -n argocd port-forward svc/argocd-server 8443:443
```
Log in at https://localhost:8443 with the printed password.

You applied exactly one manifest by hand: `argocd/bootstrap/root-app.yaml`. It points at `argocd/apps/`, which contains the AppProject and two child Applications. This is the **app-of-apps** pattern.

Compare the two child apps:

| | `gitops-lab-dev` | `gitops-lab-prod` |
|---|---|---|
| Sync | Automated, prune, self-heal | Manual |
| Replicas | HPA min 2, frontend 2 | HPA min 3, frontend 3 |
| Tags change via | CI commit | Promotion PR |

Sync prod once by hand from the UI (it starts OutOfSync by design).

Get the app URL:
```bash
kubectl -n gitops-lab-dev get svc frontend -w     # wait for EXTERNAL-IP
```

**Checkpoint:** the page shows `Environment: dev`, versions matching your short commit SHA, and at least two colours in the strip.

---

## Module 5 · The full loop (20 min)

**Goal:** see one change travel from commit to pod.

1. In `apps/backend/app.py`, add a tip of your own to `TIPS`.
2. Commit and push to `main`.
3. Keep the app page open with auto-refresh on. Watch in this order: Actions run → bot commit → Argo CD `gitops-lab-dev` goes OutOfSync then Syncing → new colours appear in the strip and the backend version changes.

**Checkpoint:** the backend version on the page equals the short SHA of your commit, and your tip shows up.

---

## Module 6 · Promote to production (15 min)

1. Actions → **promote-to-prod** → Run workflow.
2. Open the PR it created. The diff is only image tags in `k8s/overlays/prod`. Review and merge.
3. Argo CD shows `gitops-lab-prod` **OutOfSync**. Click Sync (or `argocd app sync gitops-lab-prod`).

**Checkpoint:** the prod page (`kubectl -n gitops-lab-prod get svc frontend`) shows the same versions as dev.

---

## Module 7 · Day-2 exercises (45 min, pick any)

**7a. Drift and self-heal.** Run `kubectl -n gitops-lab-dev delete deploy frontend`. Watch Argo CD recreate it within seconds. Now do the same in prod. What's different, and why might you want that?

**7b. Rollback with Git.** Push a backend change, then `git revert` the bot's `deploy(dev)` commit and push. The previous image returns. Compare with Argo CD's own History → Rollback, and discuss why the Git way is the one that sticks when auto-sync is on.

**7c. A broken release.** Change the readiness probe path in `k8s/base/backend.yaml` to `/nope` and push. Because `maxUnavailable: 0`, the old pods keep serving while the new one never becomes Ready. Find the cause in Argo CD (resource tree → pod → events), then fix it with a commit.

**7d. Autoscaling.** Generate load and watch the HPA add pods and new colours appear:
```bash
kubectl -n gitops-lab-dev run load --rm -it --image=busybox:1.36 --restart=Never -- \
  sh -c 'while true; do wget -q -O- http://backend:8000/api/info >/dev/null; done'
kubectl -n gitops-lab-dev get hpa backend -w
```
Then explain why the Deployment in Git has no `replicas` field.

**7e. Guardrails.** Change `argocd/apps/dev.yaml` to deploy into namespace `default` and push. The AppProject refuses it. Read the error and revert.

---

## Stretch goals

- Split into an app repo and a config repo; CI in the app repo opens PRs against the config repo.
- Replace the LoadBalancer Service with the Gateway API (`gatewayClassName: gke-l7-global-external-managed`) and a managed certificate.
- Make the cluster private (private nodes) and add Cloud NAT so Argo CD can still reach GitHub.
- Give the backend its own Kubernetes service account bound to a Google service account with GKE Workload Identity, then read from a Cloud Storage bucket.
- Add Argo CD Image Updater and compare it with the CI-commit approach.
- Scan images with Artifact Analysis and block the promotion PR on critical CVEs.

## Clean up

```bash
./scripts/99-teardown.sh
```
