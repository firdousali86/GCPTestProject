# Shared helpers for the lab scripts.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/infra/terraform"

info() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mxx %s\033[0m\n' "$*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing tool: $1"; }
tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }
