#!/usr/bin/env bash
# Checks tooling and that the OCI profile authenticates before terraform apply.
source "$(dirname "$0")/lib.sh"
echo "profile: $PROFILE  home region: $HOME_REGION  genai region: $REGION"
oci iam region-subscription list --profile "$PROFILE" --query 'data[*]."region-name"' --raw-output | tr -d '\n '; echo
T=$(oci iam compartment list --profile "$PROFILE" --compartment-id-in-subtree true --query 'data[0]."compartment-id"' --raw-output 2>/dev/null || true)
echo "tenancy: ${T:-unknown}"
echo "GenAI model check:"; oci generative-ai model-collection list-models --compartment-id "$T" --profile "$PROFILE" --region "$REGION" --query 'data.items[*]."display-name"' --raw-output | jq -r '.[]' | grep -c . | xargs echo " models visible:"
echo "ok"
