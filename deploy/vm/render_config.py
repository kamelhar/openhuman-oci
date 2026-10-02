#!/usr/bin/env python3
"""Fetch secrets from OCI Vault with the instance principal and render the
OpenHuman core environment and model settings.

Runs from a systemd timer. Writes /opt/openhuman/core.env (bearer token, keyring,
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


MODEL_SETTINGS_METHOD = "openhuman.config_update_model_settings"
MCP_CONFIG_METHOD = "openhuman.mcp_clients_config_set"
LOCAL_AI_METHOD = "openhuman.config_update_local_ai_settings"


def schema_methods():
    """Method names advertised by the core's public /schema."""
    import requests
    try:
        schema = requests.get(f"{RPC}/schema", timeout=10).json()
        return {m.get("method") for m in schema.get("methods", []) if isinstance(m, dict)}
    except Exception as e:
        print(f"schema fetch failed: {e}")
        return set()


BROWSER_MCP_URL = "http://playwright-mcp:8931/mcp"


def register_mcp(secrets, cfg, state, core_token):
    """Declare the core's MCP servers: the headless browser always, the Database
    Tools MCP Server once a user token is in Vault. config_set replaces the whole
    document, so both are sent together."""
    servers = {"browser": {
        "url": BROWSER_MCP_URL,
        "description": "Headless Chromium via Playwright MCP: navigate, click, type, read pages, screenshots",
    }}
    token = ""
    if cfg.get("SECRET_MCP_USER_TOKEN"):
        token = secret_value(secrets, cfg["SECRET_MCP_USER_TOKEN"])
    if token not in ("", "PENDING") and cfg.get("MCP_ENDPOINT"):
        servers["oracle-db"] = {
            "url": cfg["MCP_ENDPOINT"],
            "headers": {"Authorization": f"Bearer {token}"},
            "description": "Oracle AI Database via the OCI Database Tools MCP Server",
        }
    fp = hashlib.sha256(json.dumps(servers, sort_keys=True).encode()).hexdigest()
    if state.get("mcp_hash") == fp:
        return
    try:
        rpc(MCP_CONFIG_METHOD, {"mcpServers": servers}, core_token)
        state["mcp_hash"] = fp
        save_state(state)
        print(f"MCP servers registered: {sorted(servers)}")
    except Exception as e:
        print(f"MCP registration failed: {e}")


RESEARCHER = {
    "id": "researcher",
    "name": "Web researcher",
    "description": "Use for focused web research on one topic, company, drug or trial: it searches, reads 2-3 authoritative pages and returns verified facts with source URLs.",
    "enabled": True,
    "system_prompt": ("You are a careful research sub-agent. For the topic you are given: call web_search_tool, then web_fetch "
                      "the 2-3 most authoritative pages (prefer official sites, regulators, peer-reviewed or major news; skip pages "
                      "that return 403). Return 3-5 verified facts as bullets, each ending with its source URL. Never invent facts or "
                      "URLs. Execute tool calls immediately, one tool call per message; do not narrate."),
    "tool_allowlist": ["web_search_tool", "web_fetch", "tool_search"],
    "tool_denylist": ["shell", "apply_patch", "spawn_async_subagent", "spawn_parallel_agents"],
    "tags": ["research", "demo"],
    "metadata": {"created_by": "openhuman-oci renderer"},
}


def ensure_agents(state, core_token):
    """Register the researcher sub-agent and let the orchestrator delegate to it."""
    fp = hashlib.sha256(json.dumps(RESEARCHER, sort_keys=True).encode()).hexdigest()
    if state.get("agents_hash") == fp:
        return
    try:
        try:
            rpc("openhuman.agent_registry_create_custom", RESEARCHER, core_token)
        except Exception as e:
            if "exists" not in str(e).lower():
                rpc("openhuman.agent_registry_update", RESEARCHER, core_token)
        orch = rpc("openhuman.agent_registry_get", {"id": "orchestrator"}, core_token) or {}
        agent = orch.get("agent", orch)
        allow = list(((agent.get("subagents") or {}).get("allowlist")) or [])
        if "researcher" not in allow:
            allow.append("researcher")
            rpc("openhuman.agent_registry_update", {"id": "orchestrator", "subagents": {"allowlist": allow}}, core_token)
        state["agents_hash"] = fp
        save_state(state)
        print("agents ensured: researcher registered and allowed for the orchestrator")
    except Exception as e:
        print(f"agent registry update failed: {e}")


# First upstream release that can take the encrypted_file master key from the
# environment (tinyhumansai/openhuman PR #6935, issue #6926): anything newer than
# 0.64.10. On 0.64.10 a container has no keychain and no way to receive the key,
# so the plaintext file keyring on the encrypted block volume is the only option.
LAST_RELEASE_WITHOUT_MASTER_KEY = (0, 64, 10)


def version_tuple(v):
    parts = []
    for piece in str(v).lstrip("v").split("."):
        digits = "".join(ch for ch in piece if ch.isdigit())
        parts.append(int(digits) if digits else 0)
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


def keyring_env(cfg, secrets):
    """Return the OPENHUMAN_KEYRING_* lines for core.env.

    KEYRING_BACKEND (from Terraform var.keyring_backend) is auto, file or
    encrypted_file. auto = encrypted_file with the Vault-held master key when the
    release supports it and the secret is configured, else file. A bootstrap.env
    written before the master-key secret existed simply has no
    SECRET_KEYRING_MASTER_KEY and stays on file until it is re-rendered.
    """
    mode = (cfg.get("KEYRING_BACKEND") or "auto").strip().lower()
    secret_id = cfg.get("SECRET_KEYRING_MASTER_KEY", "").strip()
    supported = version_tuple(cfg.get("OPENHUMAN_VERSION", "0")) > LAST_RELEASE_WITHOUT_MASTER_KEY
    if mode == "auto":
        mode = "encrypted_file" if (supported and secret_id) else "file"
    if mode == "encrypted_file":
        if not secret_id:
            print("keyring: encrypted_file requested but SECRET_KEYRING_MASTER_KEY is missing; falling back to file")
            return ["OPENHUMAN_KEYRING_BACKEND=file"]
        if not supported:
            print(f"keyring: release {cfg.get('OPENHUMAN_VERSION')} cannot take a master key; forcing encrypted_file anyway as requested")
        key = secret_value(secrets, secret_id).strip()
        if len(key) != 64 or any(ch not in "0123456789abcdefABCDEF" for ch in key):
            print("keyring: master key secret is not 64 hex characters; falling back to file")
            return ["OPENHUMAN_KEYRING_BACKEND=file"]
        return ["OPENHUMAN_KEYRING_BACKEND=encrypted_file", f"OPENHUMAN_KEYRING_MASTER_KEY={key}"]
    return ["OPENHUMAN_KEYRING_BACKEND=file"]


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
    keyring_lines = keyring_env(cfg, secrets)

    lines = [
        f"OPENHUMAN_CORE_TOKEN={core_token}",
        f"BACKEND_URL={cfg['TINYHUMANS_BACKEND_URL']}",
        "OPENHUMAN_APP_ENV=production",
        *keyring_lines,
        # local-openai mode: the core treats OCI GenAI's OpenAI-compatible endpoint
        # as a caller-owned runtime, which needs no TinyHumans session.
        f"LOCAL_OPENAI_URL={cfg['GENAI_INFERENCE_URL']}",
        # Web search through the SearXNG container (no provider key needed).
        "OPENHUMAN_SEARXNG_ENABLED=true",
        "OPENHUMAN_SEARXNG_BASE_URL=http://searxng:8080",
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

    if core_healthy():
        register_mcp(secrets, cfg, state, core_token)
        ensure_agents(state, core_token)

    if genai_key in ("", "PENDING"):
        print("GenAI API key not yet in Vault; skipping model settings")
        return 0

    mode = cfg.get("INFERENCE_MODE", "local-openai")
    model = cfg["GENAI_CHAT_MODEL"]
    if mode == "byok-cloud":
        # Custom cloud route. Upstream gates this behind an active TinyHumans
        # session or API key (OPENHUMAN_BACKEND_API_KEY).
        desired = {
            "inference_url": cfg["GENAI_INFERENCE_URL"],
            "api_key": genai_key,
            "default_model": model,
            "embeddings_provider": "ollama:bge-m3",
        }
    else:
        # Session-free: every role pinned to the local-openai runtime, whose
        # endpoint is LOCAL_OPENAI_URL and whose bearer is local_ai.api_key.
        temp = cfg.get("GENAI_TEMPERATURE", "").strip()
        role = f"local-openai:{model}" + (f"@{temp}" if temp else "")
        desired = {
            "inference_url": "",
            "api_key": "",
            "default_model": model,
            "primary_cloud": "",
            "chat_provider": role,
            "reasoning_provider": role,
            "agentic_provider": role,
            "coding_provider": role,
            "vision_provider": role,
            "memory_provider": role,
            "learning_provider": role,
            "embeddings_provider": "ollama:bge-m3",
        }
    desired_for_hash = dict(desired, mode=mode, key_fp=hashlib.sha256(genai_key.encode()).hexdigest()[:12])
    desired_hash = hashlib.sha256(json.dumps(desired_for_hash, sort_keys=True).encode()).hexdigest()
    if state.get("model_settings_hash") == desired_hash:
        print("model settings already applied")
        return 0

    if not core_healthy():
        print("core not healthy yet; will retry")
        return 0

    method = os.environ.get("OPENHUMAN_RPC_MODEL_SETTINGS", MODEL_SETTINGS_METHOD)
    local_ai_method = os.environ.get("OPENHUMAN_RPC_LOCAL_AI", LOCAL_AI_METHOD)
    advertised = schema_methods()
    if advertised and method not in advertised:
        print(f"{method} not in /schema; available model-settings methods: "
              f"{sorted(n for n in advertised if n and 'model_settings' in n)}")
        return 0

    try:
        # Ollama runtime for embeddings (the model is named by embeddings_provider).
        rpc(local_ai_method, {
            "runtime_enabled": True,
            "opt_in_confirmed": True,
            "provider": "ollama",
            "base_url": "http://ollama:11434",
            "api_key": genai_key,  # bearer for the local-openai runtime
            "usage_embeddings": True,
        }, core_token)
        # inference_url + api_key + default_model: the core completes the BYOK
        # route (registers the provider, pins chat/reasoning/agentic/coding).
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
