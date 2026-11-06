# Zugriff: Benutzer, Gruppen, Rechte

authentik ist der einzige IdP. Rechte hängen an Gruppen, nicht an einzelnen Apps.

| Gruppe | Zugriff | Mitglieder |
|---|---|---|
| `homelab-admins` | alle Apps (Komodo, Übersicht intern, Notizen, whoami) | `akadmin` (automatisch) |
| `homelab-users` | Übersicht intern, Notizen, whoami — **nicht** Komodo | – |

Mechanik: je App eine Expression-Policy

```python
return ak_is_group_member(request.user, name="<gruppe>") \
    or ak_is_group_member(request.user, name="homelab-admins")
```

gebunden als `PolicyBinding` an die Application. Ohne passende Gruppe antwortet authentik
mit „You do not have access to this application". Angelegt und aktualisiert von
`scripts/authentik-bootstrap.py` (idempotent), Zuordnung über `APP_GROUPS`
(Default: `komodo:homelab-admins, home:homelab-users, whoami:homelab-users,
notes:homelab-users`).

## Benutzer anlegen

UI: *Directory → Users → New* (Benutzername, Name, Passwort) → *Directory → Groups →
`homelab-users` → Add user*. Ohne Gruppenzugehörigkeit ist das Konto wirkungslos.

## Prüfen ohne Login

```bash
AUTHENTIK_TOKEN=$(grep AK_BOOTSTRAP_TOKEN stacks/komodo/secrets.env | cut -d= -f2) \
  python3 scripts/authentik-verify-acl.py
```

Das Skript testet jede Policy gegen `akadmin` (muss passen) und einen temporären
Benutzer ohne Gruppe (darf nicht passen), danach wird der Testbenutzer gelöscht:

```
App       akadmin (admin)   ohne Gruppe Ergebnis
komodo    True              False       OK
home      True              False       OK
whoami    True              False       OK
```

## Gruppen ändern

- Andere Zuordnung: `APP_GROUPS` beim Bootstrap setzen, Skript erneut laufen lassen —
  Policy-Name und Bindung werden nachgezogen.
- Zusätzliche Gruppe: in authentik anlegen und in `APP_GROUPS` eintragen; die Policies
  der anderen Apps bleiben unverändert.
