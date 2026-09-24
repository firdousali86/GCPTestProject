# -----------------------------------------------------------------------------
# APIs  (AWS/Azure: services are "on" by default; in GCP you enable them per project)
# -----------------------------------------------------------------------------
locals {
  apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  service            = each.value
  disable_on_destroy = false
}

# -----------------------------------------------------------------------------
# Network  (VPC is GLOBAL in GCP; subnets are regional. Pods/Services use
# secondary ranges = "VPC-native" cluster, similar to AWS VPC CNI / Azure CNI)
# -----------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

resource "google_compute_subnetwork" "gke" {
  name                     = "${var.prefix}-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.10.0.0/20"
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }
}

# -----------------------------------------------------------------------------
# Node identity: a dedicated least-privilege service account instead of the
# Compute Engine default SA. It needs to pull images from Artifact Registry.
# -----------------------------------------------------------------------------
resource "google_service_account" "gke_nodes" {
  account_id   = "${var.prefix}-nodes"
  display_name = "GKE nodes (${var.prefix})"
  depends_on   = [google_project_service.apis]
}

resource "google_project_iam_member" "gke_nodes" {
  for_each = toset([
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# -----------------------------------------------------------------------------
# GKE Autopilot  (≈ EKS Auto Mode / AKS Automatic: no node pools to manage,
# billed per pod resource request)
# -----------------------------------------------------------------------------
resource "google_container_cluster" "autopilot" {
  name     = "${var.prefix}-gke"
  location = var.region

  enable_autopilot = true

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.gke.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  release_channel {
    channel = "REGULAR"
  }

  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.gke_nodes.email
      oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }

  # Lab setting so `terraform destroy` works. Keep true in real environments.
  deletion_protection = false

  depends_on = [google_project_iam_member.gke_nodes]
}

# -----------------------------------------------------------------------------
# Artifact Registry  (≈ ECR / ACR)
# -----------------------------------------------------------------------------
resource "google_artifact_registry_repository" "apps" {
  location      = var.region
  repository_id = var.gar_repo
  format        = "DOCKER"
  description   = "Images for the GKE GitOps lab"
  depends_on    = [google_project_service.apis]
}

# -----------------------------------------------------------------------------
# Keyless CI auth: Workload Identity Federation for GitHub Actions
# (≈ AWS IAM OIDC provider + AssumeRoleWithWebIdentity /
#    Azure Entra app with federated credentials). No JSON keys anywhere.
# -----------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "${var.prefix}-gh-pool"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.actor"      = "assertion.actor"
  }

  # Only tokens minted for THIS repo are accepted.
  attribute_condition = "assertion.repository == \"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "github_ci" {
  account_id   = "${var.prefix}-github-ci"
  display_name = "GitHub Actions CI (${var.prefix})"
  depends_on   = [google_project_service.apis]
}

# CI can push images to this one repository only.
resource "google_artifact_registry_repository_iam_member" "ci_writer" {
  location   = google_artifact_registry_repository.apps.location
  repository = google_artifact_registry_repository.apps.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.github_ci.email}"
}

# Let workflows from the GitHub repo impersonate the CI service account.
resource "google_service_account_iam_member" "github_wif" {
  service_account_id = google_service_account.github_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}
