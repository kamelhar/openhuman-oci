#!/usr/bin/env bash
# Run one SQL statement against the pilot ADB from inside the VCN (on the VM,
# through the bastion tunnel on DEMO_SSH_PORT), using the instance principal to
# read the ADMIN password from Vault. Prints a Markdown table.
# Usage: sql-vm.sh "select ..." [max_rows]
source "$(dirname "$0")/lib.sh"
PORT="${DEMO_SSH_PORT:-2222}"
SQL="$1"; MAXROWS="${2:-10}"
CS="$(tfjson adb | jq -r .tls_low_connect_string)"; SEC="$(tfjson secret_ids | jq -r .adb_admin_password)"
ssh -q -p "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15 ubuntu@127.0.0.1 \
  "sudo DSN='$CS' SEC='$SEC' SQL=\"\$(cat)\" MAXROWS='$MAXROWS' /opt/openhuman/venv/bin/python - <<'PY'
import os, base64, oci, oracledb
signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
pw = base64.b64decode(oci.secrets.SecretsClient({'region': 'ca-toronto-1'}, signer=signer)
        .get_secret_bundle(os.environ['SEC']).data.secret_bundle_content.content).decode()
conn = oracledb.connect(user='ADMIN', password=pw, dsn=os.environ['DSN']); cur = conn.cursor()
cur.execute(os.environ['SQL']); rows = cur.fetchmany(int(os.environ['MAXROWS'])); cols = [d[0].lower() for d in cur.description]
def fmt(v):
    if v is None: return ''
    if hasattr(v, 'strftime'): return v.strftime('%Y-%m-%d')
    s = str(v); return s if len(s) <= 48 else s[:45] + '...'
print('| ' + ' | '.join(cols) + ' |'); print('|' + '---|' * len(cols))
for r in rows: print('| ' + ' | '.join(fmt(v) for v in r) + ' |')
PY" <<< "$SQL"
