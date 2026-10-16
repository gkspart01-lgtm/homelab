#!/usr/bin/env bash
# Im Ziel: aus dem Anker klonen, SOPS/age initialisieren, OpenTofu pruefen und
# in Laborgroesse anwenden. Beweist: aus dem Repo entsteht die Umgebung neu.
source "$(dirname "$0")/lib.sh"

IP="$(cat "$LAB_DIR/target-ip.txt" 2>/dev/null || echo "$TARGET_IP_ONLY")"
wait_for_ssh "$IP" 10 || die "kein SSH auf $IP"

log "Git + Repo aus dem Anker"
tssh "$IP" "command -v git >/dev/null || (apt-get update -qq && apt-get install -y -qq git)"
tssh "$IP" "[ -d /root/homelab-iac/.git ] || git clone -q '$GIT_URL' /root/homelab-iac; git -C /root/homelab-iac pull -q --ff-only || true; git -C /root/homelab-iac log --oneline -1"

log "SOPS/age-Schluessel im Ziel erzeugen"
tssh "$IP" "bash /root/homelab-iac/scripts/age-init.sh | tail -4"

log "OpenTofu installieren und Konfiguration validieren"
tssh "$IP" 'command -v tofu >/dev/null || { mkdir -p /usr/local/bin; curl -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/i.sh && chmod +x /tmp/i.sh && /tmp/i.sh --install-method standalone --install-path /usr/local/bin --skip-verify >/dev/null; }; tofu version | head -1'
tssh "$IP" 'cd /root/homelab-iac/tofu && tofu init -input=false -no-color >/dev/null && tofu validate -no-color'

log "tfvars aus dem API-Token des Hosts bauen"
tssh "$IP" 'set -e
cd /root/homelab-iac/tofu
TOKEN=$(awk "/^tofu@pve!opentofu/ {print \$NF; exit}" /root/tofu-api-token.txt 2>/dev/null || echo "")
[ -n "$TOKEN" ] || TOKEN="PLATZHALTER"
KEY=$(cut -d" " -f1,2 /root/.ssh/authorized_keys | head -1)
python3 ../scripts/make-tfvars.py \
  --endpoint "https://$(ip -4 -o addr show scope global | awk "{print \$4}" | cut -d/ -f1 | head -1):8006/" \
  --token "tofu@pve!opentofu=${TOKEN}" \
  --node "$(hostname -s)" \
  --ssh-key "$KEY"'

log "plan in Produktionsgroesse (RAM-Budget sichtbar machen)"
tssh "$IP" 'cd /root/homelab-iac/tofu && tofu plan -no-color -input=false -lock=false 2>&1 | tail -25'

log "TOFU_LAB_APPLY=${TOFU_LAB_APPLY:-0}"
if [ "${TOFU_LAB_APPLY:-0}" = "1" ]; then
  log "apply in Laborgroesse (nur LXC, kleine RAM-Werte)"
  tssh "$IP" 'cd /root/homelab-iac/tofu && tofu apply -auto-approve -no-color -lock=false -var-file=../lab/target/nodes.lab.tfvars | tail -20'
fi
log "DEPLOY OK"
