"""gitops-lab backend: a tiny API that reports which pod served the request.

Being able to see the pod name and version makes rolling updates, scaling,
rollbacks and load balancing visible during the lab.
"""
import os
import random
import socket
import time

from fastapi import FastAPI

VERSION = os.getenv("APP_VERSION", "dev")
ENVIRONMENT = os.getenv("APP_ENV", "local")
STARTED = time.time()

TIPS = [
    "A GCP project is the unit of billing, IAM and quotas, like an AWS account or an Azure subscription.",
    "GCP VPCs are global. Subnets are regional. One VPC can span every region.",
    "GKE Autopilot bills per pod resource request, similar to EKS Fargate and AKS virtual nodes.",
    "Artifact Registry replaces the older Container Registry, and is GCP's ECR / ACR.",
    "Workload Identity Federation lets GitHub Actions call GCP with no JSON keys, like AWS OIDC roles.",
    "GKE Workload Identity maps a Kubernetes SA to a Google SA, like IRSA on EKS or Entra Workload ID on AKS.",
    "IAM roles in GCP are granted on a resource (project, bucket, repo) to a principal, not attached to users as policies.",
    "gcloud config configurations work like AWS CLI profiles for switching projects and accounts.",
]

app = FastAPI(title="gitops-lab backend", version=VERSION)


@app.get("/healthz")
def healthz():
    """Liveness probe: the process is up."""
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    """Readiness probe: ready to receive traffic."""
    return {"status": "ready"}


@app.get("/api/info")
def info():
    return {
        "service": "backend",
        "version": VERSION,
        "environment": ENVIRONMENT,
        "pod": socket.gethostname(),
        "uptime_seconds": round(time.time() - STARTED, 1),
    }


@app.get("/api/tip")
def tip():
    return {"tip": random.choice(TIPS)}
