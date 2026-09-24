output "cluster_name" {
  value = google_container_cluster.autopilot.name
}

output "region" {
  value = var.region
}

output "registry" {
  description = "Image registry prefix used in the Kustomize overlays"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.apps.repository_id}"
}

output "wif_provider" {
  description = "Value for the GitHub variable WIF_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "wif_service_account" {
  description = "Value for the GitHub variable WIF_SERVICE_ACCOUNT"
  value       = google_service_account.github_ci.email
}

output "get_credentials_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.autopilot.name} --region ${var.region} --project ${var.project_id}"
}

output "project_id" {
  value = var.project_id
}

output "github_repo" {
  value = var.github_repo
}
