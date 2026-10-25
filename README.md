# Homelab Architecture Plan

**Status:** approved 2026-10-25 — implementation running on `pve2` (192.168.181.99). See *Implementation status* below.
**Language:** English.

## Goals and constraints

- Rebuild the environment from versioned configuration after a host or disk failure.
- Use Proxmox VE, OpenTofu, cloud-init, Docker Compose, and SOPS + age; no Kubernetes or Ansible.
- Serve family users, with selected services reachable remotely.
- No home-router port forwarding and no Cloudflare. An IONOS VPS is the public edge; the home connection is behind CGNAT.
- Target host: HP Spectre x360 13-ae043ng, i7-8550U, 16 GB soldered RAM, one M.2 slot, USB storage. RAM cannot be upgraded.[9]
- Treat 16 GB as a hard ceiling. Immich's documented baseline is already 6 GB RAM and two CPU cores; phase services in and measure real peaks.[12]

## Proposed architecture

```mermaid
graph LR
  F[Family devices] --> DNS[IONOS DNS<br/>service.hl0.mehrwert.icu]
  DNS --> VPS[IONOS VPS · frps<br/>public TCP 443]
  VPS -->|frp tunnel, initiated from home| FRPC[frpc at home]
  FRPC --> RP[Traefik<br/>TLS termination + routing]
  RP --> AUTH[SSO / forward-auth<br/>where compatible]
  AUTH --> PUB[Selected public services]

  LAN[Home LAN clients] -->|split DNS| RP
  ADMIN[Administrator] -->|WireGuard, separate admin path| MGMT[Proxmox / SSH / private Homepage]
  RP --> PRIV[Private services]
  PVE[Proxmox VE] --> DOCKER[Debian VM<br/>Docker Compose]
  PVE --> HA[Home Assistant OS VM]
  DOCKER --> DATA[SSD: databases and app state]
  DOCKER --> BULK[HDD data pool, design TBD]
  DATA --> BACKUP[Encrypted offsite backup<br/>+ offline copy]
  BULK --> BACKUP
```

- **Public edge:** frp is the leading proposal because it is a focused reverse tunnel with token authentication, while Pangolin's own VPS guidance recommends 2 GB RAM. Keep frp small: allow only the required ports, require authentication and encrypted tunnel transport, keep its admin interface private, and update it deliberately.[1][2][13]
- **TLS:** public HTTPS terminates at Traefik at home; obtain certificates with an IONOS DNS-01 challenge. The public VPS forwards traffic but holds no application data or routing policy.
- **Admin access:** keep Proxmox, SSH, and private dashboards off the public path. Use WireGuard as a separate management route; never expose the Proxmox UI through the service tunnel.
- **Services:** one Debian VM hosts Compose stacks; Home Assistant OS remains a separate VM. Start with a small set and add services only after measuring RAM. No per-service VM unless isolation or a specific appliance requirement justifies it.
- **Data:** M.2 for the host, databases, and application state. Bulk media may use per-disk filesystems plus mergerfs/SnapRAID after disk inventory. SnapRAID parity is not real-time, so it is not appropriate protection for frequently changing live databases.[8]
- **Backups:** keep guest/config backups, encrypted offsite copies of irreplaceable data, and an offline copy. SnapRAID and a second directory on the same disks are not independent backups. Perform a restore test before loading family data.

## Network and IP plan

The known home network is `192.168.176.0/21` with gateway `192.168.178.1`. The agreed address blocks are:

| Purpose | Reserved range |
|---|---|
| Primary / real lab | `192.168.181.100–150` |
| Disposable test lab | `192.168.181.200–250` |

Before assigning addresses, verify that neither block overlaps the FRITZ!Box DHCP pool or existing leases. Keep a small IP/name inventory in the architecture plan. Use stable addresses for infrastructure, not every short-lived guest.

**Addressing policy:**

- Prefer DHCP reservations for stable VMs, bound to explicitly stable virtual MAC addresses.
- If reservation is unavailable or unsuitable, configure a static address inside the reserved block and outside the DHCP pool.
- Use normal DHCP for disposable test guests.
- Do not mix static assignments and the DHCP pool; never rely on “that address looks unused.”

**Name resolution:** use DNS names, not literal IPs, in service settings. Compose services talk to each other by Compose service name. Use internal DNS for LAN-only names and split DNS for public service names. mDNS is useful for device discovery (including some smart-home devices), but not as the dependency for stable service-to-service connections.

## Remote access, Homepage, and SSO

Homepage should **not** be restricted to the tunnel by default. The useful default is one private Homepage behind SSO, available from the LAN and through WireGuard. A second, separate public overview is optional: list only intentionally public services and expose no internal names, admin links, API widgets, or credentials.

A reverse-proxy login gate is not automatically compatible with every native app. Prefer each service’s own login or native OIDC where supported. Immich supports OIDC and documents reverse-proxy requirements for headers and mobile endpoints; Home Assistant requires trusted-proxy configuration when reverse-proxied, so test browser and mobile-client flows.[3][4][5]

| Option | Advantages | Trade-offs | Proposed use |
|---|---|---|---|
| **Authelia** | Configuration in files; proxy authorization; good fit for a light login gate | More manual user/config management; test each app and client | First SSO pilot for Homepage and compatible browser-only services.[6] |
| **authentik** | Richer identity provider, UI, policies, and proxy provider for apps without native auth | More components and operational weight | Revisit if family self-service or broader OIDC/SAML management becomes important.[7] |
| **Tinyauth** | Small, simple proxy-auth layer | Not a full identity platform; fewer identity features | Alternative if a login wall is enough, not if full SSO is required |
| **Native app auth / OIDC** | Best compatibility with service APIs and mobile apps | Accounts may still be managed per service | Default for Immich, Nextcloud, Vaultwarden, and other native clients |
| **VPN-only** | Small public attack surface; simple service auth model | Family members need a VPN client | Default for Proxmox, SSH, Home Assistant administration, and internal dashboards |

**Initial exposure policy:** Homepage admin view, Proxmox, SSH, and Home Assistant are private/VPN-only. Public access is enabled service by service only after authentication, backups, and mobile-client tests pass. Vaultwarden must not be put behind a generic proxy login without testing Bitwarden clients; its own authentication remains required.

## Storage decision — deliberately not final yet

Do not finalize a pool or format disks until the inventory is complete: capacity, 2.5/3.5-inch, enclosure/bridge, power supply, SMART health, and data already on each disk.

- The laptop has one internal M.2 slot; it cannot provide an internal SSD mirror. A second SSD over Thunderbolt would still be an external device, not a reason to treat it as a reliable mirror.
- ZFS is not ruled out because ECC is mandatory: OpenZFS calls ECC strongly recommended, not required. For this laptop, USB-drive reliability, memory budget, and operating simplicity are the reasons to defer it.[11]
- For mostly static bulk files, mergerfs + SnapRAID is a candidate. Its parity must be synced and does not protect changes made since the last sync.[8]
- Do not store live databases on the SnapRAID pool. Keep app state and databases on SSD; back them up separately.
- Start with the simplest reliable set of powered drives. Add a multi-disk pool only if its power, enclosure, and USB stability are proven.
- RAID/parity improves availability; it does not replace an independent backup.

## Build sequence and gates

```mermaid
gantt
  title Proposed order — gates, not calendar promises
  dateFormat X
  axisFormat %s
  section Decide
  Inventory, IPs, exposure policy :p0, 0, 1
  section Rehearse
  Repeatable disposable lab       :p1, after p0, 2
  section Host
  PVE install and network          :p2, after p1, 1
  Storage decision and burn-in     :p3, after p2, 1
  section Core
  Guests and LAN-only services     :p4, after p3, 1
  Backup and restore test          :p5, after p4, 1
  section Remote access
  frp, TLS, SSO pilot              :p6, after p5, 1
  Family services, one at a time   :p7, after p6, 2
  section Prove
  Two clean rebuild rounds         :p8, after p7, 2
```

1. **Decide:** inventory drives, reserve the IP blocks outside DHCP, identify the IONOS DNS zone/API access, and classify each service as public, VPN-only, or LAN-only.
2. **Rehearse:** keep a stable repository source outside the disposable VM; rebuild one test target repeatedly. Do not run parallel test hosts on the current constrained test hardware unless resource headroom is measured.
3. **Install the real host:** PVE, fixed/reserved host address, stable Ethernet adapter, lid/power/cooling behavior verified after reboot. The unattended installer’s disk selector must be checked against the real NVMe device before use.[10]
4. **Build locally first:** storage and guests, then services on LAN only. Add Home Assistant, Homepage, and the first Compose stacks.
5. **Backup gate:** restore one guest and one application database into a scratch target. No family data before this passes.
6. **Expose one test service:** configure frp, DNS-01 TLS, and the SSO pilot. Verify from a mobile network and test native clients.
7. **Add family services gradually:** Paperless, Immich, Nextcloud, SilverBullet, SparkyFitness, Vaultwarden, and Hermes are candidates—not a promise that all fit simultaneously in 16 GB.
8. **Prove rebuildability:** two consecutive successful rebuilds from the repository; document any manual action before calling the plan complete.

## Open decisions before implementation

- Exact drive inventory and whether the current largest disk should be data or parity.
- Which services must be public; which may require VPN.
- Whether Authelia is enough or family self-service makes authentik worthwhile.
- IONOS DNS/API details and whether the wildcard is for `*.hl0.mehrwert.icu`.
- Final individual IPs within the two reserved ranges, after checking the DHCP pool.
- Offsite-backup target and budget.

## Sources

[1] https://github.com/fatedier/frp — frp — official GitHub repository
[2] https://docs.pangolin.net/self-host/choosing-a-vps — Pangolin — choosing a VPS
[3] https://docs.immich.app/administration/reverse-proxy — Immich — reverse proxy
[4] https://docs.immich.app/administration/oauth — Immich — OAuth/OIDC authentication
[5] https://www.home-assistant.io/docs/configuration/remote — Home Assistant — remote access and reverse proxy
[6] https://www.authelia.com/reference/guides/proxy-authorization — Authelia — proxy authorization
[7] https://docs.goauthentik.io/add-secure-apps/providers/proxy — authentik — proxy provider
[8] https://www.snapraid.it/manual — SnapRAID — official manual
[9] https://h10032.www1.hp.com/ctg/Manual/c05811755.pdf — HP Spectre x360 13 service manual
[10] https://pve.proxmox.com/wiki/Automated_Installation — Proxmox VE — automated installation
[11] https://openzfs.github.io/openzfs-docs/Project%20and%20Community/FAQ.html — OpenZFS FAQ — memory and ECC
[12] https://docs.immich.app/install/requirements — Immich — installation requirements
[13] https://github.com/fatedier/frp/blob/dev/conf/frps_full_example.toml — frp — full frps configuration example

## Implementation status on pve2 (2026-10-25)

`pve2` is the Proxmox VE host built for the rehearsal phase: 4 vCPU, 12 GB RAM
(11.3 GB usable), 319 GB disk – LVM-thin `local-lvm` (201 GB) plus `local` (92 GB).

| Guest | ID | Type | Size | Address | Purpose |
|---|---|---|---|---|---|
| `debian13-cloud-template` | 9000 | VM template | 2C / 2 GB / 10 GB | – | Debian 13.7 genericcloud + cloud-init + qemu-guest-agent; clone source for all later VMs |
| `docker01` | 200 | VM (clone) | 4C / 6 GB / 64 GB | 192.168.181.100/21 | Compose host (Traefik, Vaultwarden, Paperless, SilverBullet) |
| `haos` | 201 | VM (image import) | 2C / 2 GB / 32 GB | DHCP (192.168.178.74) | Home Assistant OS 18.3, Core 2026.10.4, onboarding completed |
| `probe` | 220 | LXC | 1C / 512 MB / 4 GB | 192.168.181.101/21 | IaC probe: proves the container path from the repository |

OpenTofu budget output: `ram_total_mb = 8704`, `ram_reserve_mb = 2560` (host 11 264 MB).
Host-side ballooning (set on the *outer* PVE, not inside pve2): `memory=12288`,
`balloon=8192` — the outer host may reclaim 4 GB, the guest never drops below 8 GB.

## Reproduce current state (from zero)

All commands run from the operator workstation (outside pve2). The OpenTofu state lives
in `tofu/terraform.tfstate` (gitignored).

### 1. Provision pve2 + template + guests via OpenTofu

```bash
# a) On the outer PVE: create VM pve2 (11264 MB RAM, 319 GB disk), rename to pve2.fritz.box,
#    disable Enterprise repos, enable no-subscription, add SSH key, create API token
#    tofu@pve!opentofu with role Tofu (see privileges below).
#    → This step is one-time manual work; everything after is IaC.

# b) On pve2: build the Debian-13-cloud-template (VM 9000)
ssh root@192.168.181.99 'bash -s' < tofu/build-template9000.sh
#    Result: VM 9000 template, 10 GB disk, cloud-init, qemu-guest-agent, cleaned.

# c) Operator workstation: copy tfvars + set credentials
cd tofu
cp nodes.auto.tfvars.example nodes.auto.tfvars
#    Edit nodes.auto.tfvars:
#      endpoint      = "https://192.168.181.99:8006/api2/json"
#      token_id      = "tofu@pve!opentofu"
#      token_secret  = "<your-token-secret>"
#      ssh_private_key = "~/.ssh/id_ed25519"   # path to the PRIVATE key file

# d) Initialize and apply
tofu init
tofu plan
tofu apply
#    Creates: docker01 (VM 200), probe (LXC 220), haos (VM 201).
#    Outputs: ram_total_mb, ram_reserve_mb, ipv4 map.
```

API token role `Tofu` privileges (on pve2):
```
VM.Allocate VM.Audit VM.Clone VM.Config.CPU VM.Config.CDROM VM.Config.Cloudinit
VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options
VM.GuestAgent.Audit VM.GuestAgent.Unrestricted VM.PowerMgmt Datastore.Allocate
Datastore.AllocateSpace Datastore.Audit Pool.Allocate SDN.Use Sys.Audit
```
Missing `SDN.Use`, `VM.Config.Cloudinit`, `VM.Config.CDROM` or GuestAgent audit
privileges cause HTTP 403 during `apply`.

### 2. Ballooning on the outer PVE (optional but recommended)

On the physical Proxmox host (the one running pve2 as a nested VM):

```bash
# VM-ID of pve2 on the outer host (e.g. 102):
qm set <ID> --memory 12288 --balloon 8192
qm stop <ID> && qm start <ID>
#    Now the outer host may reclaim up to 4 GB; pve2 keeps min. 8 GB.
```

### 3. Bootstrap docker01 (Docker Engine + Compose plugin)

```bash
# Run as root on docker01 (or via sudo from debian user):
cd /opt/homelab/scripts
sudo bash bootstrap-docker.sh
#    Installs docker-ce, docker-compose-plugin, enables docker service,
#    adds debian user to docker group.
```

### 4. Deploy the Edge stacks (Traefik + authentik + whoami + frp)

```bash
# On docker01 (or from operator workstation via SSH):
docker network create edge

cd /opt/homelab/stacks/edge
cp .env.example .env            # set DOMAIN=hl0.mehrwert.icu
docker compose up -d

cd ../authentik
cp .env.example .env
#    Generate secrets:
#    AUTHENTIK_POSTGRESQL_PASSWORD=$(openssl rand -hex 24)
#    AUTHENTIK_SECRET_KEY=$(openssl rand -base64 48 | tr -d "\n")
#    AUTHENTIK_BOOTSTRAP_TOKEN=$(openssl rand -hex 32)
#    AUTHENTIK_BOOTSTRAP_PASSWORD=$(openssl rand -base64 24)   # change after first login
#    Paste into .env
docker compose up -d
#    Wait ~60s for authentik health endpoint and blueprints (11 default flows).

cd ../whoami
cp .env.example .env            # DOMAIN=hl0.mehrwert.icu
docker compose up -d
```

### 5. Authentik SSO bootstrap (one-time API calls)

```bash
# On operator workstation: SSH tunnel to authentik's localhost API port
ssh -f -N -L 19000:127.0.0.1:9000 debian@192.168.181.100

# Run bootstrap (creates Proxy Provider, Application, wires Embedded Outpost,
# patches outpost config with authentik_host):
AUTHENTIK_URL=http://127.0.0.1:19000 \
AUTHENTIK_TOKEN=$(grep AUTHENTIK_BOOTSTRAP_TOKEN stacks/authentik/.env | cut -d= -f2) \
DOMAIN=hl0.mehrwert.icu APP_NAME=whoami \
python3 scripts/authentik-bootstrap.py

# Close tunnel when done
pkill -f "19000:127.0.0.1:9000"
```

### 6. Verify the chain (no public DNS needed)

```bash
EDGE_IP=192.168.181.100 DOMAIN=hl0.mehrwert.icu python3 scripts/smoke-test-edge.py
# Expected:
# 1) OK HTTP :80 -> HTTPS
# 2) OK App ohne Sitzung -> authentik-Login
# 3) OK authentik-Health durch Traefik
# 4) OK authorize leitet in den Login-Flow
# 5) OK Flow-Executor liefert Login-Maske
```

### 7. (Optional) Test the frp tunnel locally

```bash
# On docker01: runs a throwaway frps + frpc on test ports 18080/18443
bash scripts/test-frp-tunnel.sh
# Proves: HTTP->301 to HTTPS, HTTPS->302 to authentik login (full chain survives tunnel).
```

### 8. Browser test (with local hosts override)

Add to `/etc/hosts` (Linux/macOS) or `C:\Windows\System32\drivers\etc\hosts` (Windows):

```
192.168.181.100 auth.hl0.mehrwert.icu whoami.hl0.mehrwert.icu traefik.hl0.mehrwert.icu
```

Open `https://whoami.hl0.mehrwert.icu/` → login at `https://auth.hl0.mehrwert.icu/`
(user `akadmin`, password from `AUTHENTIK_BOOTSTRAP_PASSWORD`) → back to whoami with
`X-Authentik-Username` headers visible.

---

## What is NOT yet done (open items)

1. **Public VPS**: frps install on IONOS VPS, tunnel with real ports 80/443.
2. **IONOS DNS**: A records for `auth.`, `whoami.`, `traefik.`, later `*.` → VPS IP.
3. **Let's Encrypt DNS-01**: put `IONOS_API_KEY`, `IONOS_API_SECRET`, `ACME_EMAIL`
   into `stacks/edge/.env`; Traefik will switch from self-signed to valid certs.
4. **Timezone on HA**: still UTC → set to Europe/Berlin in HA UI (Settings → System → General).
5. **Restore test** (Gate before further apps): `tofu destroy -target=...` + re-apply proves State → running guest.
## Edge stack on `docker01` (2026-10-25)

Three Compose stacks from `stacks/` run on `docker01`, all routed through Traefik and
gated by authentik (details: `stacks/README.md`):

| Stack | Role | Address |
|---|---|---|
| `edge` | Traefik v3.7 — HTTP→HTTPS, TLS, Docker-label routing, dashboard behind SSO | `:80`, `:443` |
| `authentik` | SSO / identity provider (2026.8.5) + PostgreSQL 16 + Redis 7 | `https://auth.hl0.mehrwert.icu` |
| `whoami` | Test service proving routing + forward-auth | `https://whoami.hl0.mehrwert.icu` |
| `frp` | frpc client for the tunnel to the public VPS (frps lives there) | outbound to `<VPS>:7000` |

`scripts/smoke-test-edge.py` verifies the chain without public DNS (hostnames are
resolved to the edge IP, self-signed TLS accepted):

```
1) OK   HTTP :80 leitet auf HTTPS — 301 -> https://whoami.hl0.mehrwert.icu/
2) OK   App ohne Sitzung -> authentik-Login — 302 -> https://auth.hl0.mehrwert.icu/application/o/authorize/
3) OK   authentik-Health durch Traefik — 200
4) OK   authorize leitet in den Login-Flow — .../if/flow/default-authentication-flow/
5) OK   Flow-Executor liefert Login-Maske — ak-stage-identification
```

`scripts/test-frp-tunnel.sh` runs frps as a local stand-in and proves the tunnel carries
real traffic: HTTP through the tunnel answers `301 -> https://whoami...`, HTTPS through
the tunnel answers `302 -> https://auth.../application/o/authorize/` (i.e. the full
forward-auth chain survives the tunnel).

Two findings worth keeping:

- The **embedded** authentik outpost builds browser URLs from `AUTHENTIK_HOST` (and from
  `authentik_host` in the outpost's DB config, which wins). `AUTHENTIK_HOST_BROWSER`
  only applies to standalone outposts — without the right value the login redirect
  points at `http://localhost/`.
- Every protected host needs a **second Traefik router** for
  `PathPrefix(/outpost.goauthentik.io/)` pointing at the outpost; otherwise the
  forward-auth callback cannot complete.

Open for the public path: an IONOS VPS running `frps` (config template in
`stacks/frp/frps.toml.example`), the DNS records for `auth.` and `whoami.`, and the
IONOS DNS-API credentials to switch Traefik from the self-signed certificate to
Let's Encrypt DNS-01.
