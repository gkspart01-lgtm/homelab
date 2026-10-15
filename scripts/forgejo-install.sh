#!/bin/bash
# Install Forgejo (latest stable 16.0.6) inside this Debian 13 LXC container.
# Hinweis: Zugangsdaten/Passwoerter sind hier durch <PLATZHALTER> ersetzt. Duplikat-Skript mit echten Werten liegt auf dem jeweiligen Host.
# Idempotent-ish: safe to re-run, it reinstalls the binary but keeps data.
set -euo pipefail

FJ_VERSION=16.0.6
ARCH=amd64
BASE="https://code.forgejo.org/forgejo/forgejo/releases/download/v${FJ_VERSION}"
BIN="forgejo-${FJ_VERSION}-linux-${ARCH}"
HOST_IP=192.168.181.51

export DEBIAN_FRONTEND=noninteractive
echo "=== 1. packages ==="
apt-get update -qq
apt-get install -y -qq git curl ca-certificates nginx openssh-client xz-utils

echo "=== 2. system user 'git' ==="
if ! id git >/dev/null 2>&1; then
    adduser --system --shell /bin/bash --gecos 'Git Version Control' \
        --group --disabled-password --home /home/git git
fi
# host keys for Forgejo's built-in SSH server (it uses the system host keys)
ssh-keygen -A >/dev/null 2>&1 || true

echo "=== 3. download + verify Forgejo ${FJ_VERSION} ==="
cd /tmp
curl -fsSLO "$BASE/$BIN"
curl -fsSLO "$BASE/$BIN.sha256"
sha256sum -c "$BIN.sha256"
install -o root -g root -m 0755 "$BIN" /usr/local/bin/forgejo
rm -f "/tmp/$BIN" "/tmp/$BIN.sha256"
/usr/local/bin/forgejo --version

echo "=== 4. directories ==="
mkdir -p /etc/forgejo /var/log/forgejo
mkdir -p /var/lib/forgejo/{repositories,lfs,avatars,attachments,indexers,actions_log,queues}
chown -R git:git /var/lib/forgejo /var/log/forgejo /etc/forgejo
chmod 750 /var/lib/forgejo

echo "=== 5. app.ini ==="
if [ ! -f /etc/forgejo/app.ini ] || ! grep -q '^SECRET_KEY' /etc/forgejo/app.ini; then
    SECRET_KEY=$(su -s /bin/bash git -c "/usr/local/bin/forgejo generate secret SECRET_KEY 2>/dev/null" || openssl rand -base64 42)
    INTERNAL_TOKEN=$(su -s /bin/bash git -c "/usr/local/bin/forgejo generate secret INTERNAL_TOKEN 2>/dev/null" || openssl rand -base64 42)
    [ -n "${SECRET_KEY:-}" ] || SECRET_KEY=$(openssl rand -base64 42)
    [ -n "${INTERNAL_TOKEN:-}" ] || INTERNAL_TOKEN=$(openssl rand -base64 42)
    if [ -f /etc/forgejo/app.ini ]; then
        # re-running: keep the file, only inject the missing secrets
        sed -i "/^SECRET_KEY/d;/^INTERNAL_TOKEN/d" /etc/forgejo/app.ini
        printf 'SECRET_KEY = %s\nINTERNAL_TOKEN = %s\n' "$SECRET_KEY" "$INTERNAL_TOKEN" >> /etc/forgejo/app.ini
    else
        cat > /etc/forgejo/app.ini <<EOF
APP_NAME = Forgejo
RUN_USER = git
WORK_PATH = /var/lib/forgejo
SECRET_KEY = ${SECRET_KEY}
INTERNAL_TOKEN = ${INTERNAL_TOKEN}

[server]
PROTOCOL = http
DOMAIN = ${HOST_IP}
HTTP_ADDR = 127.0.0.1
HTTP_PORT = 3000
ROOT_URL = http://${HOST_IP}/
DISABLE_SSH = false
START_SSH_SERVER = true
SSH_LISTEN_HOST = 0.0.0.0
SSH_LISTEN_PORT = 2222
SSH_PORT = 2222
LFS_START_SERVER = true
OFFLINE_MODE = false

[database]
DB_TYPE = sqlite3
PATH = /var/lib/forgejo/forgejo.db

[repository]
ROOT = /var/lib/forgejo/repositories

[lfs]
PATH = /var/lib/forgejo/lfs

[log]
ROOT_PATH = /var/log/forgejo
MODE = console

[service]
DISABLE_REGISTRATION = true
DEFAULT_BRANCH = main
DEFAULT_KEEP_EMAIL_PRIVATE = true
ENABLE_BASIC_AUTHENTICATION = true

[security]
INSTALL_LOCK = true
PASSWORD_HASH_ALGO = pbkdf2
MIN_PASSWORD_LENGTH = 8

[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = https://code.forgejo.org

[session]
COOKIE_SECURE = false
EOF
    fi
fi
chown root:git /etc/forgejo/app.ini
chmod 640 /etc/forgejo/app.ini

echo "=== 6. systemd unit ==="
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
ProtectSystem=full
ProtectHome=false

[Install]
WantedBy=multi-user.target
EOF

echo "=== 7. nginx reverse proxy on port 80 ==="
cat > /etc/nginx/sites-available/forgejo <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${HOST_IP};

    client_max_body_size 512M;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -sf /etc/nginx/sites-available/forgejo /etc/nginx/sites-enabled/forgejo
rm -f /etc/nginx/sites-enabled/default
nginx -t

echo "=== 8. start services ==="
systemctl daemon-reload
systemctl enable --now forgejo
systemctl enable --now nginx >/dev/null 2>&1 || systemctl restart nginx
sleep 8
systemctl --no-pager --lines=0 status forgejo nginx | grep -E "^\s*●|Active:|Loaded:" || true

echo "=== 9. admin account ==="
su -s /bin/bash git -c "/usr/local/bin/forgejo admin user create --admin --username falko --password '<ROOT-PASSWORT>' --email 'baumilauni@gmail.com' --must-change-password=false --config /etc/forgejo/app.ini" 2>&1 | tail -3 || \
su -s /bin/bash git -c "/usr/local/bin/forgejo admin user create --admin --username falko --password '<ROOT-PASSWORT>' --email 'baumilauni@gmail.com' --config /etc/forgejo/app.ini" 2>&1 | tail -3
su -s /bin/bash git -c "/usr/local/bin/forgejo admin user list --config /etc/forgejo/app.ini" 2>&1 | tail -5 || true

echo "=== 10. verification ==="
echo "--- listening ports ---"; ss -tlnp | grep -E ':80 |:3000 |:2222 ' || true
echo "--- local API ---"; curl -s -m 10 http://127.0.0.1:3000/api/v1/version; echo
echo "--- via nginx (http host header) ---"
curl -s -m 10 -o /dev/null -w "http://127.0.0.1/ -> %{http_code}\n" -H "Host: ${HOST_IP}" http://127.0.0.1/
curl -s -m 10 -H "Host: ${HOST_IP}" http://127.0.0.1/api/v1/version; echo
echo "--- SSH (built-in git ssh server) ---"
(exec 3<>/dev/tcp/127.0.0.1/2222; head -c 40 <&3; exec 3<&-) 2>/dev/null | tr -d '\0' | head -1
echo
echo "--- forgejo log tail ---"
journalctl -u forgejo --no-pager -n 5 -o cat || true
echo "INSTALL-OK"
