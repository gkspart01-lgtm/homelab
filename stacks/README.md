# IaC-Ebene 3: Dienste als Compose-Stacks

Ein Ordner pro Stack, alles im Git, Secrets als SOPS-verschlüsselte `.env`.

```
stacks/
  edge/          Traefik (TLS per Let's Encrypt DNS-01 über IONOS)
  vpn/           WireGuard zum VPS (Public Edge hinter CGNAT)
  vaultwarden/   Passwortmanager (der eine Dienst mit manuellem Bootstrap)
  forgejo/       Git-Host (oder LXC, siehe tofu/)
  paperless/     paperless-ngx
  silverbullet/  Notizen
  immich/        Phase 2, ohne ML-Container
  nextcloud/     Phase 3, schlank (kein AIO)
```

Muster jedes Stacks:
* `compose.yaml` – Image, Volumes, Netzwerk, `restart: unless-stopped`
* `.env.sops` – verschlüsselte Variablen (`sops -e -i .env`), im Git
* `README.md` – Zweck, Ports, Backup-Pfad, Restore-Kommando

Deploy:
```bash
git pull
make up STACK=vaultwarden     # sops exec-env + docker compose up -d
```
`make up` liegt als `scripts/deploy.sh` im Repo und macht nichts anderes,
als Secrets zu entschlüsseln und Compose zu starten.
