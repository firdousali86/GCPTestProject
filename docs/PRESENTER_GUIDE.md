# Presenter Guide

For trainers running this lab with consultants who already know AWS and/or Azure. They don't need Kubernetes or CI/CD explained from scratch; they need the GCP-specific mental model and a working GitOps pattern they can reuse at clients.

## Before the session

- **Dry run** the full quick start in the README in your own project the day before. Keep that environment up to use for the live demo and as a fallback if a trainee's provisioning stalls.
- **Projects:** one GCP project per trainee is cleanest. If they must share one, give each a different `prefix` and `gar_repo` in `terraform.tfvars`; everything is namespaced by prefix.
- **Quota:** check regional CPU and external IP quotas if many trainees share a project or billing account.
- **Pin Argo CD:** set `ARGOCD_VERSION=vX.Y.Z` for the class so everyone sees the same UI.
- **Pre-provision option:** if time is short, run Module 2 for everyone before class and start at Module 3.

## Suggested agenda (one day)

| Time | Block | Format |
|---|---|---|
| 0:00 | Why GitOps, and the architecture diagram | Talk, 15 min |
| 0:15 | GCP for AWS/Azure people (cheat sheet in README) | Talk + Q&A, 20 min |
| 0:35 | Modules 0–1 | Hands-on |
| 1:10 | Module 2 (start Terraform, then walk through `main.tf` while it runs) | Hands-on + code walkthrough |
| 1:45 | Break | |
| 2:00 | Module 3 | Hands-on |
| 2:45 | Module 4 | Hands-on |
| 3:30 | Lunch | |
| 4:15 | Live demo: the full loop (script below) | Demo, 10 min |
| 4:25 | Modules 5–6 | Hands-on |
| 5:10 | Module 7 exercises, then group debrief | Hands-on + discussion |
| 6:10 | Teardown together, wrap-up | |

For a half-day version, pre-provision infra, skip Module 1 and do only 7a and 7b.

## Talking points by module

**GCP mental model (the part they get wrong most often)**
- Project ≈ account/subscription. Folders and organization sit above it, like AWS Organizations OUs or Azure management groups.
- IAM is "who has which role **on which resource**". There are no identity-attached policy documents like AWS; roles are granted at org, folder, project or individual resource level and inherit downwards.
- Service accounts are both an identity and a resource you can grant access *to* (that's what `workloadIdentityUser` on the SA is).
- VPCs are global. One VPC, subnets in many regions, no peering needed between regions.

**Terraform (Module 2)**
- Point out `enable_autopilot = true` and that there are no node pools at all. Compare with managed node groups on EKS or system/user pools on AKS.
- Autopilot enforces sensible security defaults and bills per pod request, which is why every container in `k8s/base` has explicit requests.
- The dedicated node service account replaces the Compute Engine default SA, which historically had project Editor. That's a common client audit finding.

**Keyless CI (Module 3)**
- Walk the token exchange: GitHub OIDC token → Security Token Service → impersonate the CI service account → short-lived access token. It's the same flow as `aws-actions/configure-aws-credentials` with `role-to-assume`, or `azure/login` with federated credentials.
- Ask: "What stops someone else's repo from using our pool?" Answer: the `attribute_condition`. Then ask how they'd scope it to the `main` branch only (add `assertion.ref == 'refs/heads/main'`).

**GitOps (Module 4)**
- CI has zero cluster credentials. The cluster pulls. This is the single biggest security argument for GitOps at clients.
- The pipeline's output is a Git commit, so audit, approval and rollback are Git operations everyone already understands.
- Dev is auto-sync with self-heal; prod is manual sync. Talk about when clients should and shouldn't auto-sync prod.

## Live demo script (about 10 minutes)

Use your pre-built environment. Have three windows ready: the dev app page, Argo CD on the dev app's resource tree, and GitHub Actions.

1. **Show steady state.** App page with two or three colours in the strip. "Each colour is a pod answering."
2. **Make a visible change.** Edit a tip in `apps/backend/app.py`, commit, push. Narrate the Actions run: tests, OIDC auth, push, bot commit.
3. **Point at Git.** Show the bot's commit diff: one line, the image tag.
4. **Watch Argo CD.** OutOfSync → Syncing. New ReplicaSet appears in the tree.
5. **Watch the app.** New colours join, old ones fade out, and the backend version flips to the new SHA with no failed (striped) requests. That's the rolling update with `maxUnavailable: 0`.
6. **Drift.** `kubectl -n gitops-lab-dev delete deploy frontend`. The page blips, Argo CD puts it back. "Git wins."
7. **Rollback.** `git revert` the bot commit, push, watch the old version return.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `google-github-actions/auth` fails with `unauthorized_client` or permission denied | `github_repo` in tfvars doesn't match the repo exactly (case, org name, fork) | Fix tfvars and `terraform apply` |
| Auth works but push is denied | Wrong `GAR_REPO`/`GCP_REGION` variable, or IAM still propagating | Check the variables; wait a minute and re-run |
| Bot commit fails with 403 | Workflow permissions are read-only | Settings → Actions → General → Read and write permissions |
| Promotion workflow can't open a PR | PR creation by Actions is disabled | Tick "Allow GitHub Actions to create and approve pull requests" |
| Pods in `ImagePullBackOff` | CI hasn't pushed yet, or placeholders weren't replaced | Run both workflows; `grep -r PLACEHOLDER k8s argocd` should return nothing |
| Argo CD app says `repository not accessible` | Private repo without credentials | Make it public for the lab or add repo credentials |
| Argo CD app says destination not permitted | Namespace doesn't match `gitops-lab-*` in the AppProject | Fix the Application's destination namespace |
| Pods Pending for a few minutes | Autopilot is provisioning nodes | Normal on first deploy; `kubectl get events` shows scale-up |
| Frontend CrashLoop with `host not found in upstream "backend"` | Backend Service missing in that namespace | Check the backend resources synced; the frontend recovers on restart |
| `terraform apply` fails creating the identity pool after a teardown | Pools are soft-deleted for 30 days | Change `prefix` in tfvars |
| `terraform destroy` hangs on the VPC | A LoadBalancer's forwarding rule still exists | Use `99-teardown.sh`, which deletes apps first; or delete the leftover forwarding rules in the console |

## Debrief questions

1. Where do secrets live in this design, and what would you add for application secrets? (Secret Manager with the CSI driver or External Secrets Operator.)
2. How would you run this for five client environments and three clusters? (ApplicationSets, cluster generators, a config repo per client.)
3. What in this lab maps directly to the EKS or AKS setup you built last month, and what's genuinely different?
4. Which gate would you keep for prod at a regulated client: the PR, the manual sync, or both?
