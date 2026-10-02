#!/usr/bin/env bash
# First-boot bootstrap for the OpenHuman core VM (Ubuntu 24.04 aarch64).
# Idempotent: safe to re-run. Reads /opt/openhuman/bootstrap.env written by cloud-init.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
BASE=/opt/openhuman
source "$BASE/bootstrap.env"

log() { echo "[bootstrap $(date -u +%FT%TZ)] $*"; }

# ---- workspace volume --------------------------------------------------------
DEV=/dev/oracleoci/oraclevdb
log "waiting for workspace volume $DEV"
for _ in $(seq 1 60); do [ -e "$DEV" ] && break; sleep 10; done
if [ -e "$DEV" ]; then
  if ! blkid "$DEV" >/dev/null 2>&1; then
    log "formatting $DEV"
    mkfs.ext4 -L openhuman "$DEV"
  fi
  mkdir -p "$BASE/data"
  grep -q "LABEL=openhuman" /etc/fstab || echo "LABEL=openhuman $BASE/data ext4 defaults,nofail 0 2" >> /etc/fstab
  mountpoint -q "$BASE/data" || mount "$BASE/data"
else
  log "WARN volume not found, using boot volume for data"
  mkdir -p "$BASE/data"
fi
mkdir -p "$BASE/data/workspace" "$BASE/data/projects" "$BASE/data/ollama" "$BASE/data/playwright-out"
chmod 0777 "$BASE/data/playwright-out"
chown -R 10001:10001 "$BASE/data/workspace" "$BASE/data/projects"

# ---- docker ------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "installing docker"
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker

# ---- host firewall (Ubuntu OCI images ship restrictive iptables) -------------
if ! iptables -C INPUT -p tcp --dport 7788 -j ACCEPT 2>/dev/null; then
  iptables -I INPUT 5 -p tcp --dport 7788 -j ACCEPT
  command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save || true
fi

# ---- assets ------------------------------------------------------------------
for f in Dockerfile.core compose.yaml render_config.py openhuman-render.service openhuman-render.timer searxng-settings.yml; do
  curl -fsSL "$ASSETS_BASE_URL/$f" -o "$BASE/$f"
done
# SearXNG config with a per-host secret key (never committed).
mkdir -p "$BASE/searxng"
if [ ! -f "$BASE/searxng/settings.yml" ]; then
  sed "s/replaced-at-boot/$(openssl rand -hex 32)/" "$BASE/searxng-settings.yml" > "$BASE/searxng/settings.yml"
fi

# ---- python env for the secret/config renderer ------------------------------
if [ ! -x "$BASE/venv/bin/python" ]; then
  python3 -m venv "$BASE/venv"
fi
"$BASE/venv/bin/pip" install --quiet --upgrade pip oci tomli-w requests

# ---- core image from the upstream release tarball ---------------------------
IMG_TAG="${OPENHUMAN_VERSION}-$(sha256sum "$BASE/Dockerfile.core" | cut -c1-8)"
if ! docker image inspect "openhuman-core:${IMG_TAG}" >/dev/null 2>&1; then
  log "building openhuman-core:${IMG_TAG}"
  docker build --build-arg "OPENHUMAN_VERSION=${OPENHUMAN_VERSION}" -t "openhuman-core:${IMG_TAG}" -f "$BASE/Dockerfile.core" "$BASE"
fi
docker tag "openhuman-core:${IMG_TAG}" openhuman-core:local

# ---- first render of secrets + config (creates core.env) --------------------
"$BASE/venv/bin/python" "$BASE/render_config.py" --no-restart || log "WARN first render failed (secrets may not be ready yet); timer will retry"

# ---- services ----------------------------------------------------------------
cd "$BASE"
docker compose -f compose.yaml up -d
# embeddings model for the memory tree
docker compose -f compose.yaml exec -T ollama ollama pull bge-m3 || log "WARN bge-m3 pull failed; timer will retry"

install -m 0644 "$BASE/openhuman-render.service" /etc/systemd/system/
install -m 0644 "$BASE/openhuman-render.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now openhuman-render.timer
log "done"
