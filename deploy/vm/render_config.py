#!/usr/bin/env python3
"""Fetch secrets from OCI Vault with the instance principal and render the
OpenHuman core environment and model settings.

Runs from a systemd timer. Writes /opt/openhuman/core.env (bearer token,
backend URL, optional TinyHumans key) and, once the core is healthy and the
GenAI API key secret is populated, pushes the BYOK inference settings through
the core's JSON-RPC so the route is completed the way the desktop app does it.
Restarts the core container only when core.env changed.
"""
import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

BASE = Path("/opt/openhuman")
ENV_FILE = BASE / "bootstrap.env"
CORE_ENV = BASE / "core.env"
STATE = BASE / "render_state.json"
RPC = "http://127.0.0.1:7788"


def load_env(path):
    out = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            out[k] = v
    return out


def secret_value(client, secret_id):
    import oci  # noqa
    bundle = client.get_secret_bundle(secret_id=secret_id).data
    return base64.b64decode(bundle.secret_bundle_content.content).decode()


def load_state():
    if STATE.exists():
        try:
            return json.loads(STATE.read_text())
        except Exception:
            pass
    return {}


def save_state(s):
    STATE.write_text(json.dumps(s, indent=2))


def core_healthy():
    import requests
    try:
        return requests.get(f"{RPC}/health", timeout=5).status_code == 200
    except Exception:
        return False


def rpc(method, params, token):
    import requests
    body = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    r = requests.post(f"{RPC}/rpc", json=body, headers={"Authorization": f"Bearer {token}"}, timeout=60)
    r.raise_for_status()
    data = r.json()
    if "error" in data:
        raise RuntimeError(f"{method}: {data['error']}")
    return data.get("result")


def discover_method(token, *needles):
    """Find an RPC method whose name contains all needles (schema is public)."""
    import requests
    try:
        schema = requests.get(f"{RPC}/schema", timeout=10).json()
    except Exception as e:
        print(f"schema fetch failed: {e}")
        return None
    names = []
    if isinstance(schema, dict):
        for key in ("methods", "rpc", "procedures"):
            if key in schema and isinstance(schema[key], (list, dict)):
                names = list(schema[key].keys()) if isinstance(schema[key], dict) else [m.get("name") if isinstance(m, dict) else m for m in schema[key]]
                break
        if not names:
            names = list(schema.keys())
    elif isinstance(schema, list):
        names = [m.get("name") if isinstance(m, dict) else m for m in schema]
    for n in names:
        if n and all(x in n for x in needles):
            return n
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-restart", action="store_true")
    args = ap.parse_args()

    cfg = load_env(ENV_FILE)
    state = load_state()

    import oci
    signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
    secrets = oci.secrets.SecretsClient({"region": cfg["OCI_REGION"]}, signer=signer)

    core_token = secret_value(secrets, cfg["SECRET_CORE_TOKEN"])
    th_key = secret_value(secrets, cfg["SECRET_TINYHUMANS_KEY"])
    genai_key = secret_value(secrets, cfg["SECRET_GENAI_API_KEY"])

    lines = [
        f"OPENHUMAN_CORE_TOKEN={core_token}",
        f"BACKEND_URL={cfg['TINYHUMANS_BACKEND_URL']}",
        "OPENHUMAN_APP_ENV=production",
        "RUST_LOG=info",
    ]
    if th_key and th_key != "NONE":
        lines.append(f"OPENHUMAN_BACKEND_API_KEY={th_key}")
    new_env = "\n".join(lines) + "\n"
    new_hash = hashlib.sha256(new_env.encode()).hexdigest()

    if state.get("env_hash") != new_hash:
        CORE_ENV.write_text(new_env)
        os.chmod(CORE_ENV, 0o600)
        state["env_hash"] = new_hash
        state["model_settings_hash"] = None  # force re-push after restart
        save_state(state)
        print("core.env updated")
        if not args.no_restart:
            subprocess.run(["docker", "compose", "-f", str(BASE / "compose.yaml"), "up", "-d"], cwd=BASE, check=False)
            subprocess.run(["docker", "restart", "openhuman-core"], check=False)
            for _ in range(30):
                if core_healthy():
                    break
                time.sleep(5)

    if genai_key in ("", "PENDING"):
        print("GenAI API key not yet in Vault; skipping model settings")
        return 0

    desired = {
        "inference_url": cfg["GENAI_INFERENCE_URL"],
        "api_key": genai_key,
        "default_model": cfg["GENAI_CHAT_MODEL"],
        "embeddings_provider": "ollama:bge-m3",
    }
    desired_hash = hashlib.sha256(json.dumps(desired, sort_keys=True).encode()).hexdigest()
    if state.get("model_settings_hash") == desired_hash:
        print("model settings already applied")
        return 0

    if not core_healthy():
        print("core not healthy yet; will retry")
        return 0

    method = os.environ.get("OPENHUMAN_RPC_MODEL_SETTINGS") or discover_method(core_token, "model", "settings")
    local_ai_method = os.environ.get("OPENHUMAN_RPC_LOCAL_AI") or discover_method(core_token, "local_ai", "set")
    if not method:
        print("could not discover a model-settings RPC method; see /schema")
        return 0

    try:
        if local_ai_method:
            rpc(local_ai_method, {
                "runtime_enabled": True,
                "opt_in_confirmed": True,
                "provider": "ollama",
                "base_url": "http://ollama:11434",
                "embedding_model_id": "bge-m3",
                "usage_embeddings": True,
            }, core_token)
        rpc(method, desired, core_token)
        state["model_settings_hash"] = desired_hash
        state["model_settings_method"] = method
        save_state(state)
        print(f"model settings pushed via {method}")
    except Exception as e:
        print(f"model settings push failed: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
