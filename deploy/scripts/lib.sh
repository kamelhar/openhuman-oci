# Shared helpers for the operator scripts. Source, don't execute.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${TF_DIR:-$HERE/../terraform}"
# API-key profiles only; override any session-token default inherited from the shell.
export OCI_CLI_AUTH=api_key
export PYTHONWARNINGS=ignore

tfout() { terraform -chdir="$TF_DIR" output -raw "$1"; }
tfjson() { terraform -chdir="$TF_DIR" output -json "$1"; }

tfvar() { grep -E "^[[:space:]]*$1[[:space:]]*=" "$TF_DIR/terraform.tfvars" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/'; }
PROFILE="${OCI_PROFILE:-$(tfvar oci_profile)}"
PROFILE="${PROFILE:-DEFAULT}"
REGION="$(tfjson genai | jq -r .region 2>/dev/null || echo us-chicago-1)"
HOME_REGION="${OCI_HOME_REGION:-$(tfvar region)}"
HOME_REGION="${HOME_REGION:-ca-toronto-1}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need terraform; need oci; need jq
