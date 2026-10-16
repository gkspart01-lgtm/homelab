# Secrets: SOPS + age

Regeln:
* **Niemals** Klartext-Geheimnisse ins Git. Verschlüsselt wird mit `sops -e -i .env`
  und der Public Key steht in `.sops.yaml`.
* Der **age-Private-Key** liegt auf dem Host (`/root/.config/sops/age/keys.txt`) und
  **zusätzlich offline**: ausgedruckt im Safe oder auf einem USB-Stick. Ohne ihn ist
  das Repo beim Totalverlust unlesbar – das ist der einzige nicht-automatisierbare Teil.
* Auf einem neuen Host zuerst `scripts/age-init.sh` (Schlüssel erzeugen) oder den
  Offline-Schlüssel zurückkopieren – dann `sops -d` funktioniert wieder.
* Vaultwarden bleibt der einzige Dienst, dessen Bootstrap-Passwort manuell eingegeben wird.

Alltag:
```bash
sops secrets/vaultwarden/.env      # entschlüsselt im Editor, speichert verschlüsselt
sops -d -i --in-place .env         # entschlüsseln (Deploy-Skript macht das)
```
