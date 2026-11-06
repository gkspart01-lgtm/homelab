# Troubleshooting

Symptom → Ursache → Fix. Nur Fälle, die tatsächlich aufgetreten sind.

## Traefik / Tunnel

**`works` lokal, durch den Tunnel `502` oder Redirect-Schleife.**
Der VPS terminiert TLS und schickt Klartext. Dafür gibt es den Entrypoint `webplain`
(**8081** — 8080 ist Traefiks Dashboard) ohne HTTPS-Redirect, plus `*-plain`-Router mit
`tunnel-headers@file` (`X-Forwarded-Proto: https`, `X-Forwarded-Port: 443`). Fehlt die
Middleware, baut authentik `http://`-URLs und der Browser landet in einer Schleife.

**`webplain` auf 8080 gelegt → Traefik antwortet mit dem Dashboard.**
`api.insecure` belegt 8080. Deshalb 8081.

## authentik

**Login-Redirect zeigt auf `http://localhost/`.**
Der *embedded* Outpost baut Browser-URLs aus `AUTHENTIK_HOST` **und** aus
`authentik_host` in der Outpost-Konfiguration (die gewinnt).
`AUTHENTIK_HOST_BROWSER` wirkt nur bei Standalone-Outposts. Beides setzen:
Container-Env `AUTHENTIK_HOST=https://auth.<DOMAIN>` und Outpost-`config` per API.

**Callback bleibt hängen / `404` nach dem Login.**
Jede geschützte Domain braucht einen **zweiten** Traefik-Router für
`PathPrefix('/outpost.goauthentik.io/')` mit höherer Priorität auf `authentik@file`.
Ohne ihn kann der Outpost den Callback nicht beantworten.

**App antwortet mit der authentik-Seite statt der App.**
Für die Domain existiert kein authentik-Provider. Jede Domain braucht eine eigene
Application — sonst gibt der Outpost nichts frei.

**Listen-Endpunkte (`GET /core/applications/?page_size=200`) liefern unzuverlässig.**
Einzeln per Slug abfragen (`GET /core/applications/<slug>/`); das Bootstrap-Skript macht
das inzwischen so und legt bei einem 400 auf `POST` per `PATCH` nach.

## Komodo

**Stack startet mit falschen Variablen, alte Werte gewinnen.**
Komodo erbt die Prozess-Umgebung von Core/Periphery. Eine veraltete `DOMAIN` in
`stacks/komodo/.env` überschreibt jede Stack-`.env`. Nach Änderung Core + Periphery neu
erzeugen, nicht nur `restart`.

**Variablen ändern sich im UI, aber nicht im Stack.**
Komodo rendert `[[VAR]]` beim **Schreiben** der Stack-Config. Nach dem Setzen der
Variablen `UpdateStack` + `DeployStack` aufrufen (`scripts/komodo-bootstrap.py` macht das).

**`CreateVariable` schlägt fehl.**
Bei vorhandenem Namen heißt die Operation `UpdateVariableValue` (nicht
`UpdateVariable`). Read-Endpunkte brauchen trotzdem einen JSON-Body (`{}`).

**Server bleibt `NotOk`.**
Periphery spricht TLS: `https://periphery:8120` plus `insecure_tls = true`. Ein
`http://`-Server wird nie gesund.

**Stack-Status vergleichen.**
Komodo liefert `running`, nicht `Running` — case-insensitiv prüfen.

**Zwei Secrets-Dateien → PostgreSQL-Passwort passt nicht.**
Genau eine Quelle: `stacks/komodo/secrets.env`. Bei Abweichung
`docker exec authentik-postgresql psql -U authentik -d authentik -c "ALTER USER authentik WITH PASSWORD '…'"`.

## Home Assistant

**`:8123` liefert `Connection refused`, Observer `:4357` antwortet `200`.**
VM, Netz und Supervisor laufen; nur der Core-HTTP-Server fehlt. Erst messen, dann
reparieren — weder der Konsolen-Banner `System is ready!` noch `ha core restart` →
`Command completed successfully` beweisen einen offenen Port.

```bash
qm guest exec 201 -- /bin/sh -c 'ha core info | grep -E "^(port|version)"'
qm guest exec 201 -- /bin/sh -c 'grep -n server_port /mnt/data/supervisor/homeassistant/.storage/http'
```

**Port ist 80 statt 8123.**
Der Web-Port steht in `/config/.storage/http` (`"server_port": 80`). `ha core options
--port=8123` ist **transient** und fällt beim nächsten Core-Restart zurück. Richtig:

```bash
qm guest exec 201 -- /bin/sh -c 'ha core stop'
qm guest exec 201 -- /bin/sh -c 'cp /mnt/data/supervisor/homeassistant/.storage/http /mnt/data/supervisor/homeassistant/.storage/http.bak'
qm guest exec 201 -- /bin/sh -c "sed -i 's/\"server_port\": *80/\"server_port\": 8123/' /mnt/data/supervisor/homeassistant/.storage/http"
qm guest exec 201 -- /bin/sh -c 'ha core start'
```

**Leerer `home-assistant.log.fault`, keine Logs.**
`duplicate_log_file: false` ist Default: Core loggt nur nach stdout (`docker logs
homeassistant`). Ein 0-Byte-`.fault` ist kein Fehler.

**Diagnose ohne Tastencodes.** `qm guest exec` funktioniert auf HAOS (Guest-Agent mit
exec). Bei verschachtelten Kommandos ein Skript base64-kodiert in den Gast schieben:
`qm guest exec 201 -- /bin/sh -c 'echo <b64> | base64 -d > /tmp/p.sh; sh /tmp/p.sh'`.

**Alle Reboots helfen nicht.** Dann ist es keine hängende VM, sondern Konfiguration —
Watchdog-Reboot bringt nichts (er respektiert eine Stunde Abkühlzeit und versucht es
danach erneut).

## frp (geparkt)

**`send Login request to plugin error` auf `:7001`.**
Der frps-Host erreicht sein Plugin (frps-panel, `:7200`) nicht. Liegt auf der VPS-Seite;
ohne Zugriff auf die Container/Logs dort nicht lösbar.

**`user [x] port [y] is not allowed`.**
`ports` im Panel-Token müssen **Strings** sein (`["8082"]`), Bereiche als `"10000-10200"`.
Integer werden als `int64` dekodiert und matchen nie.

**`token in login doesn't match token from configuration`.**
Der Client muss `user` **und** `metadatas.token` senden; `auth.token` wird abgelehnt.

## OpenTofu

**HTTP 403 beim Klonen.**
Der API-Rolle fehlen Rechte — typisch `SDN.Use`, `VM.Config.Cloudinit`,
`VM.Config.CDROM`, `VM.GuestAgent.Unrestricted`.

**`file_id` für Image-Import ungültig.**
Das Feld heißt `import_from`, und das Image muss unter `local:import/` liegen
(nicht `template/iso/`).
