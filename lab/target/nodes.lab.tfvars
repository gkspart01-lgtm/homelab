# Laborgroesse fuer den Ziel-Host im Test (4 GB RAM): nur LXC, kleine Werte.
# Beweist Syntax, Provider-Verhalten und Idempotenz - nicht die Produktionsgroesse.
proxmox = {
  endpoint  = "https://192.168.181.50:8006/"
  api_token = "tofu@pve!opentofu=BITTE-AUS-/root/tofu-api-token.txt"
  insecure  = true
  ssh_user  = "root"
}

defaults = {
  node         = "lab01"
  datastore    = "local-lvm"
  bridge       = "vmbr0"
  template_id  = 9000
  lxc_template = "local:vztmpl/debian-13-standard_13.1-1_amd64.tar.zst"
  searchdomain = "fritz.box"
  gateway      = "192.168.178.1"
  dns          = "192.168.178.1"
  ssh_keys     = ["ssh-ed25519 AAAA...pve"]
}

guests = {
  probe = {
    type    = "lxc"
    vmid    = 220
    cores   = 1
    memory  = 512
    disk    = 4
    ip      = "192.168.181.60/21"
    purpose = "Lab-Probe: beweist, dass aus dem Repo ein Gast entsteht"
  }
}
