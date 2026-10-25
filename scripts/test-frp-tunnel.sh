#!/usr/bin/env bash
# Prueft die frp-Kette lokal: frps (Testserver) <- frpc <- Traefik:80/443.
# Laeuft auf docker01 und raeumt hinterher auf. Der echte VPS-Tunnel ist identisch,
# nur mit echten Ports 80/443 und der VPS-Adresse.
set -euo pipefail
NET=edge
TAG=v0.71.1
TMP=$(mktemp -d)
trap 'docker rm -f frps-test frpc-test >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

cat > "$TMP/frps.toml" <<CFG
bindPort = 17000
auth.method = "token"
auth.token = "testtoken"
CFG
cat > "$TMP/frpc.toml" <<CFG
serverAddr = "frps-test"
serverPort = 17000
auth.method = "token"
auth.token = "testtoken"

[[proxies]]
name = "web-test"
type = "tcp"
localIP = "192.168.181.100"
localPort = 80
remotePort = 18080

[[proxies]]
name = "websecure-test"
type = "tcp"
localIP = "192.168.181.100"
localPort = 443
remotePort = 18443
CFG

docker run -d --name frps-test --network "$NET" -p 18080:18080 -p 18443:18443 \
  -v "$TMP/frps.toml:/etc/frp/frps.toml:ro" "fatedier/frps:$TAG" -c /etc/frp/frps.toml >/dev/null
sleep 3
docker run -d --name frpc-test --network "$NET" \
  -v "$TMP/frpc.toml:/etc/frp/frpc.toml:ro" "fatedier/frpc:$TAG" -c /etc/frp/frpc.toml >/dev/null
sleep 5

echo "=== frpc-Log ==="
docker logs frpc-test 2>&1 | tail -6
echo
echo "=== durch den Tunnel: HTTP (Port 18080) ==="
curl -s -o /dev/null -w "HTTP %{http_code} -> %{redirect_url}\n" -m 10 \
  -H "Host: whoami.hl0.mehrwert.icu" http://127.0.0.1:18080/
echo "=== durch den Tunnel: HTTPS (Port 18443) ==="
# Host-Header ohne Port setzen, sonst matcht der Traefik-Router nicht (Test-Port 18443)
curl -sk -o /dev/null -w "HTTP %{http_code} -> %{redirect_url}\n" -m 10 \
  --resolve "whoami.hl0.mehrwert.icu:18443:127.0.0.1" -H "Host: whoami.hl0.mehrwert.icu" \
  https://whoami.hl0.mehrwert.icu:18443/
echo "=== frps-Log ==="
docker logs frps-test 2>&1 | tail -4
