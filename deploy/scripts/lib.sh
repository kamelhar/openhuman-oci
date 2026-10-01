# Shared helpers for the operator scripts. Source, don't execute.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${TF_DIR:-$HERE/../terraform}"
export OCI_CLI_AUTH="${OCI_CLI_AUTH:-api_key}"
export PYTHONWARNINGS=ignore

tfout() { terraform -chdir="$TF_DIR" output -raw "$1"; }
tfjson() { terraform -chdir="$TF_DIR" output -json "$1"; }

PROFILE="${OCI_PROFILE:-$(grep -E '^\s*oci_profile' "$TF_DIR/terraform.tfvars" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' || true)}"
PROFILE="${PROFILE:-DEFAULT}"
REGION="$(tfjson genai | jq -r .region 2>/dev/null || echo us-chicago-1)"
HOME_REGION="$(grep -E '^\s*region' "$TF_DIR/terraform.tfvars" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' || echo ca-toronto-1)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need terraform; need oci; need jq
