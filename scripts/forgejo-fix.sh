#!/bin/bash
# Fix + finish the Forgejo setup inside CT 110 (idempotent).
# Hinweis: Zugangsdaten/Passwoerter sind hier durch <PLATZHALTER> ersetzt. Duplikat-Skript mit echten Werten liegt auf dem jeweiligen Host.
set -euo pipefail

echo "=== 1. let Forgejo own/manage app.ini (it writes INTERNAL_TOKEN on first start) ==="
sed -i '/^INTERNAL_TOKEN/d' /etc/forgejo/app.ini
chown git:git /etc/forgejo/app.ini /etc/forgejo
chmod 660 /etc/forgejo/app.ini

echo "=== 2. hardened but writable systemd unit ==="
cat > /etc/systemd/system/forgejo.service <<'EOF'
[Unit]
Description=Forgejo (Beyond coding. We forge.)
After=network.target
Wants=network.target

[Service]
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/forgejo
ExecStart=/usr/local/bin/forgejo web --config /etc/forgejo/app.ini
Restart=always
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=/var/lib/forgejo GITEA_CUSTOM=/var/lib/forgejo/custom
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/etc/forgejo /var/lib/forgejo /var/log/forgejo /home/git

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl restart forgejo
sleep 10
echo "=== 3. service state ==="
systemctl is-active forgejo
ss -tlnp | grep -E ':3000 |:2222 ' || true
echo "=== 4. secrets written by forgejo? ==="
grep -c '^INTERNAL_TOKEN' /etc/forgejo/app.ini

echo "=== 5. API + nginx ==="
curl -s -m 10 http://127.0.0.1:3000/api/v1/version; echo
curl -s -m 10 -o /dev/null -w "http://127.0.0.1/ (Host 192.168.181.51) -> %{http_code}\n" -H "Host: 192.168.181.51" http://127.0.0.1/

echo "=== 6. admin account ==="
su -s /bin/bash git -c "/usr/local/bin/forgejo admin user create --admin --username falko --password '<ROOT-PASSWORT>' --email 'baumilauni@gmail.com' --must-change-password=false --config /etc/forgejo/app.ini" 2>&1 | tail -2
su -s /bin/bash git -c "/usr/local/bin/forgejo admin user list --config /etc/forgejo/app.ini" 2>&1 | tail -5

echo "=== 7. built-in ssh server handshake ==="
(exec 3<>/dev/tcp/127.0.0.1/2222; timeout 3 head -c 50 <&3; exec 3<&-) 2>/dev/null | tr -d '\0'; echo
echo "=== 8. journal ==="
journalctl -u forgejo --no-pager -n 6 -o cat
echo "FIX-OK"
