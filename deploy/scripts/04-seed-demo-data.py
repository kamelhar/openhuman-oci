#!/usr/bin/env python3
"""Create a small ORDERS table in the pilot ADB so the agent has something to query.
Connects over TLS (no wallet) from an allowed client IP using the ADMIN password
stored in Vault. Requires: pip install oracledb oci
"""
import base64, json, os, subprocess, sys
import oracledb, oci

TF_DIR = os.path.join(os.path.dirname(__file__), "..", "terraform")
def tfout(name):
    return json.loads(subprocess.check_output(["terraform", f"-chdir={TF_DIR}", "output", "-json", name]))

profile = os.environ.get("OCI_PROFILE", "DEFAULT")
home_region = os.environ.get("OCI_HOME_REGION", "ca-toronto-1")
cfg = oci.config.from_file(profile_name=profile)
cfg["region"] = home_region
secrets = oci.secrets.SecretsClient(cfg)
pw = base64.b64decode(secrets.get_secret_bundle(tfout("secret_ids")["adb_admin_password"]).data.secret_bundle_content.content).decode()
dsn = tfout("adb")["tls_low_connect_string"]

conn = oracledb.connect(user="ADMIN", password=pw, dsn=dsn)
cur = conn.cursor()
cur.execute("""
begin
  execute immediate 'create table orders (
    order_id number generated always as identity primary key,
    customer varchar2(80), region varchar2(20), product varchar2(80),
    quantity number, unit_price number(10,2), status varchar2(20),
    ordered_at timestamp default systimestamp)';
exception when others then if sqlcode != -955 then raise; end if;
end;""")
rows = [
    ("Acme Corp", "NA", "Ampere A1 credits", 10, 12.5, "SHIPPED"),
    ("Globex", "EMEA", "Object Storage 1TB", 3, 23.0, "PENDING"),
    ("Initech", "APAC", "ADB Always Free", 1, 0.0, "SHIPPED"),
    ("Umbrella", "NA", "GenAI tokens 1M", 7, 2.0, "CANCELLED"),
    ("Hooli", "LATAM", "OKE basic cluster", 2, 0.0, "SHIPPED"),
]
cur.executemany("insert into orders(customer,region,product,quantity,unit_price,status) values (:1,:2,:3,:4,:5,:6)", rows)
conn.commit()
cur.execute("select count(*) from orders")
print("orders rows:", cur.fetchone()[0])
