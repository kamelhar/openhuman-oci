#!/usr/bin/env bash
# Creates an OCI Generative AI API key in the pilot compartment and stores the
# secret in the Vault secret Terraform pre-created. The key value is never printed.
source "$(dirname "$0")/lib.sh"
COMP="$(tfout compartment_id)"
SECRET_ID="$(tfjson secret_ids | jq -r .genai_api_key)"
MODEL="$(tfjson genai | jq -r .chat_model)"
NAME="${1:-openhuman-core-$(date +%Y%m%d)}"
EXPIRY_DAYS="${EXPIRY_DAYS:-365}"
EXPIRY=$(python3 -c "import datetime as d; print((d.datetime.now(d.timezone.utc)+d.timedelta(days=$EXPIRY_DAYS)).strftime('%Y-%m-%dT%H:%M:%SZ'))")

echo "checking model '$MODEL' exists in $REGION ..."
if ! oci generative-ai model-collection list-models --compartment-id "$COMP" --profile "$PROFILE" --region "$REGION" \
     --query 'data.items[*]."display-name"' --raw-output | jq -e --arg m "$MODEL" 'index($m) != null' >/dev/null; then
  echo "WARN model '$MODEL' not found in the catalogue visible to this compartment; continuing" >&2
fi

echo "creating GenAI API key '$NAME' in $REGION ..."
RESP=$(oci generative-ai api-key create --compartment-id "$COMP" --display-name "$NAME" \
        --key-details "[{\"keyName\":\"key-one\",\"timeExpiry\":\"$EXPIRY\"},{\"keyName\":\"key-two\",\"timeExpiry\":\"$EXPIRY\"}]" \
        --profile "$PROFILE" --region "$REGION")
echo "$RESP" | jq -c '.data | {id, "display-name", "lifecycle-state", keys: [.keys[]? | {"key-name", "key-mask", state}]}'

# The secret material (ApiKeyItem.key) is only returned by the create call.
KEY=$(echo "$RESP" | jq -r '.data.keys[0].key // empty')
if [ -z "$KEY" ]; then
  echo "create response has no .data.keys[0].key; fields present:" >&2
  echo "$RESP" | jq '.data.keys | map(keys)' >&2
  exit 1
fi

echo "storing in Vault secret ..."
oci vault secret update-base64 --secret-id "$SECRET_ID" --secret-content-content "$(printf %s "$KEY" | base64)" \
   --profile "$PROFILE" --region "$HOME_REGION" >/dev/null
unset KEY RESP
echo "done. The VM picks it up within ~2 minutes (openhuman-render.timer)."
