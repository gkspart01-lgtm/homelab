#!/usr/bin/env bash
# IaC-Ebene 2b: Docker-Engine + Compose-Plugin auf einem frischen Debian-13-Gast.
# Idempotent: mehrfaches Ausführen ist unschädlich.
set -euo pipefail

if command -v docker >/dev/null 2>&1; then
  echo "Docker ist bereits installiert: $(docker --version)"
else
  echo "=== Docker-Repo (offiziell) einrichten ==="
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  cat > /etc/apt/sources.list.d/docker.list <<'EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable
EOF
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

echo "=== Dienst + Rechte ==="
systemctl enable --now docker
# Arbeitsbenutzer darf Docker ohne sudo nutzen (Komfort; Root bleibt Root)
if id debian >/dev/null 2>&1; then
  usermod -aG docker debian || true
fi

echo "=== Stand ==="
docker --version
docker compose version
systemctl is-active docker
