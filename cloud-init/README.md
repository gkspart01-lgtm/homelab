# IaC-Ebene 2: cloud-init

Jede VM startet aus dem Debian-13-Template (VMID 9000) und richtet sich per cloud-init
selbst ein: Benutzer, SSH-Key, IP, DNS, Hostname. Kein Config-Management-Tool,
kein "es hat 200 Dinge angefasst".

* Die IP-/DNS-/User-Angaben kommen aus `tofu/nodes.auto.tfvars`.
* Alles Weitere passiert über die Compose-Stacks (`stacks/`), die auf dem
  Docker-Host liegen – nicht über cloud-init.

`user-data.yaml.example` zeigt das Muster für Sonderfälle (z.B. Hostname-Fix,
Zusatzpakete). Im Normalfall brauchst du es nicht.
