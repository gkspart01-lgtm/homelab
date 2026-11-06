# IaC-Ebene 1: OpenTofu + bpg/proxmox

Deklarative Beschreibung aller Gäste (VM/LXC). Kein Ansible, kein Zustands-Ping-Pong:
`tofu plan` zeigt vorher genau, was passiert.

```bash
cp nodes.auto.tfvars.example nodes.auto.tfvars   # Token + SSH-Key eintragen
tofu init
tofu plan      # Summe der RAM-Reservierung steht in ram_total_mb
tofu apply
```

- Nur `nodes.auto.tfvars` enthält Geheimnisse (API-Token) und ist gitignored.
- `enabled = false` deaktiviert einen Gast, ohne ihn zu löschen — das RAM-Budget bleibt
  reproduzierbar, auch wenn ein Dienst noch nicht laufen kann.
- Der State liegt lokal (`terraform.tfstate`, gitignored). Sichern über `vzdump` des
  Gastes bzw. ein Datei-Backup des Verzeichnisses — ohne State kein `tofu destroy`.
- Der Provider braucht SSH auf den Host (Datei-Uploads, Cloud-Init).
- Dateien: `main.tf` (Provider, VMs, LXC), `haos.tf` (HAOS als eigene UEFI-Ressource),
  `variables.tf`, `nodes.auto.tfvars.example`, `build-template9000.sh`.
