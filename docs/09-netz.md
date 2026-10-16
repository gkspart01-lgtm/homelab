# Netz: Public Edge am IONOS-VPS, dahinter alles privat

Ausgangslage: FRITZ!Box mit CGNAT (keine oeffentliche IPv4), keine Portfreigaben
gewuenscht, Domain + DNS-API bei IONOS, VPS mit 1 GB Ubuntu (root) vorhanden.

## Aufbau
```
Familien-Handy / Browser
        |  https (443)  -> DNS zeigt auf den VPS
        v
IONOS-VPS (oeffentliche IPv4/IPv6)          <-- einziger oeffentlich erreichbarer Punkt
  |  WireGuard-Tunnel (der Host waehlt AUSGEHEND, weil CGNAT nichts reinlaesst)
  v
hl0 (192.168.178.10)  ->  Traefik  ->  Dienste
```
* Der VPS macht **nur** Transport: TCP:443 per SNI/Proxy weiter durch den Tunnel.
  Alle Host-Regeln, Zertifikate und Dienstdefinitionen liegen bei dir zuhause –
  ein neuer Dienst ist eine Aenderung im `stacks/`-Repo, nicht auf dem VPS.
* Alternative (mehr Komfort, mehr Pflegeaufwand): Traefik komplett auf dem VPS.
  Ich empfehle die duenne Variante, sie bleibt reproduzierbar.
* Tunnel-Hygiene: `wg-quick` mit `PersistentKeepalive = 25`, geplanter
  Neustart der Tunnel-Schnittstelle per systemd-Timer als Sicherheitsnetz,
  `fail2ban`/nftables auf dem VPS, SSH nur per Key.

## Zertifikate: DNS-01 gegen IONOS (kein Port 80/443 nach innen)
* IONOS wird von **lego** unterstuetzt (`IONOS_API_KEY`) → Traefik bekommt
  `certificatesresolvers.ionos` mit `dnsChallenge.provider=ionos`.
* Damit sind Wildcard-Zertifikate moeglich: `*.hl0.mehrwert.icu` + `hl0.mehrwert.icu`.
* Zu klaeren: ist die DNS-Zone `mehrwert.icu` oder `hl0.mehrwert.icu`? Der
  Wildcard-Eintrag und der ACME-Zonenname richten sich danach.
* Alternative ohne Traefik: `acme.sh --dns dns_ionos` mit Deploy-Hook, falls wir
  den Edge-Proxy spaeter tauschen.

## Warum kein Cloudflare
Gewuenscht ist maximale OSS-Infrastruktur: kein Cloudflare-Tunnel, kein
Cloudflare-DNS. Der VPS ist eigene Infrastruktur mit eigenem DNS-Eintrag.

## Zugriff fuer die Familie
* **Default: WireGuard-App** auf Handys/Notebooks (Immich- und Nextcloud-Apps
  funktionieren ueber VPN). Zwei Konfigurationen: Host-Netz und "nur Dienste".
* **Oeffentlich**: nur Dienste, die es wirklich brauchen (z. B. Immich fuer
  Familienmitglieder ohne VPN). Davor gestellt wird eine Auth-Schicht
  (Authelia oder Authentik) – nie ein Dienst ohne vorgelagerte Authentifizierung,
  wenn er im Internet steht.
* Split-DNS spaeter: AdGuard Home (`.11`) + Unbound als LAN-DNS; intern zeigen
  `*.hl0.mehrwert.icu` auf `192.168.178.10`, extern auf den VPS.

## SSH-Zugang zum Host
* Nur Key-Auth (im Auto-Install-Answer-File bereits hinterlegt), Passwort-Login
  nach dem ersten Login abschalten, Port bleibt 22 (per VPN erreichbar).
* Der Host braucht **keine** oeffentliche Adresse – Remote-Arbeit laeuft ueber
  den VPS (WireGuard) oder eine TMUX-Sitzung.

## Offene Punkte
1. Zone/Root der DNS-Verwaltung bei IONOS (`mehrwert.icu` vs. `hl0.mehrwert.icu`)
   und der API-Key.
2. Welche Dienste sollen oeffentlich, welche nur per VPN erreichbar sein?
3. IPv6: FRITZ!Box hat meist Prefix-Delegation – wenn du willst, kann ein
   AAAA-Record direkt nach Hause zeigen und den VPS fuer IPv6-Clients
   weitgehend ersetzen. Fuer IPv4 bleibt der VPS noetig.
