#!/usr/bin/env bash
# Trusts the generated CA in the macOS login keychain so the desktop app accepts
# the load balancer certificate. Skip if you supplied a real certificate.
source "$(dirname "$0")/lib.sh"
OUT="$(mktemp -d)/openhuman-oci-ca.pem"
tfout lb_ca_certificate_pem > "$OUT"
echo "adding $OUT to the login keychain (you may be prompted)"
security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$OUT"
echo "trusted. Core RPC URL: $(tfout core_rpc_url)"
