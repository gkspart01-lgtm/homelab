# IaC-Ebene 1: OpenTofu + bpg/proxmox

Deklarative Beschreibung aller Gäste (VM/LXC). Kein Ansible, kein Zustands-Ping-Pong:
`tofu plan` zeigt vorher genau, was passiert.

```bash
cp nodes.auto.tfvars.example nodes.auto.tfvars   # Token + SSH-Key eintragen
tofu init
tofu plan      # Summe der RAM-Reservierung steht in ram_total_mb
tofu apply
```

* Nur die Datei `nodes.auto.tfvars` enthält Geheimnisse (Token) – sie ist in `.gitignore`
  und wird per restic gesichert.
* `enabled = false` deaktiviert einen Dienst, ohne ihn zu löschen: so bleibt das
  RAM-Budget reproduzierbar, auch wenn ein Dienst noch nicht laufen kann.
* State: liegt lokal (`terraform.tfstate`) und wird über `hosts/.../restic-backup.sh`
  offsite gesichert. Wer will, kann ihn per `sops -e` zusätzlich ins Git legen.
* Der Provider braucht SSH auf den Host (Datei-Uploads, Cloud-Init-ISO).
