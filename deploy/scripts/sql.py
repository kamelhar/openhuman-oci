#!/usr/bin/env python3
"""Run one SQL statement against the pilot ADB over TLS and print a Markdown table.
Used by the research demo for the dataset view. Needs: .venv with oracledb + oci.
Usage: sql.py "select ..." [max_rows]"""
import base64, json, os, subprocess, sys
import oracledb, oci

TF_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "terraform")
def tfout(name):
    return json.loads(subprocess.check_output(["terraform", f"-chdir={TF_DIR}", "output", "-json", name]))

profile = os.environ.get("OCI_PROFILE", "DEFAULT"); region = os.environ.get("OCI_HOME_REGION", "ca-toronto-1")
cfg = oci.config.from_file(profile_name=profile); cfg["region"] = region
pw = base64.b64decode(oci.secrets.SecretsClient(cfg).get_secret_bundle(tfout("secret_ids")["adb_admin_password"]).data.secret_bundle_content.content).decode()
conn = oracledb.connect(user="ADMIN", password=pw, dsn=tfout("adb")["tls_low_connect_string"])
cur = conn.cursor(); cur.execute(sys.argv[1]); rows = cur.fetchmany(int(sys.argv[2]) if len(sys.argv) > 2 else 10)
cols = [d[0].lower() for d in cur.description]
def fmt(v):
    if v is None: return ""
    if hasattr(v, "strftime"): return v.strftime("%Y-%m-%d")
    s = str(v); return s if len(s) <= 48 else s[:45] + "..."
print("| " + " | ".join(cols) + " |"); print("|" + "---|" * len(cols))
for r in rows: print("| " + " | ".join(fmt(v) for v in r) + " |")
