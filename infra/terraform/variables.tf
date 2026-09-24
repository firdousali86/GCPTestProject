variable "project_id" {
  description = "GCP project ID (the GCP equivalent of an AWS account / Azure subscription)"
  type        = string
}

variable "region" {
  description = "Region for GKE, Artifact Registry and the subnet"
  type        = string
  default     = "us-central1"
}

variable "prefix" {
  description = "Name prefix for all resources. Change it per trainee if several people share one project."
  type        = string
  default     = "gitops-lab"
}

variable "gar_repo" {
  description = "Artifact Registry repository name for container images"
  type        = string
  default     = "gitops-lab"
}

variable "github_repo" {
  description = "GitHub repository allowed to push images, in owner/name form, e.g. acme/gke-gitops-lab"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repo))
    error_message = "github_repo must be owner/name (e.g. acme/gke-gitops-lab), not a URL."
  }
}
