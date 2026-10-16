# Tool Choices — Options, Pros/Cons, and Why

> Every choice below is a **proposal with a reason**, not a dogma. The last column of
> every table states the condition under which the decision should be revisited.
> Star counts and last-commit dates were checked on 2026-10-16 via the GitHub API.
> RAM figures are *reported/estimated* footprints for small deployments, not measurements
> taken on this hardware — treat them as a magnitude, not a promise.

## 1. Edge transport (publishing the LAN through the CGNAT VPS)

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **frp** (fatedier/frp, 110k★, Apache-2.0, active) | single Go binary; tiny footprint (~tens of MB); TCP/UDP/HTTP/HTTPS + SNI routing; multiplexed control channel; token auth; dashboard; massively deployed | not identity-aware; one more config format; must keep it updated | **Chosen** |
| Pangolin (23k★) | identity-aware out of the box, nice UI, designed for exactly this CGNAT case | upstream asks **2 GB RAM** (1 GB only with swap); three containers (~650 MB reported) on a 1 GB VPS; more moving parts to keep patched | Rejected for *this* VPS |
| Plain WireGuard + nftables | kernel-space, fastest, no user-space proxy, fewest dependencies | you hand-write DNAT rules; more manual work; debug is less friendly | Kept as fallback |
| rathole (14k★) | Rust, similar idea, slightly leaner | smaller ecosystem/docs than frp | Alternative |
| boringproxy (1.4k★) | automatic TLS + simple UX | last release mid-2024, slow project | No |
| sish / Chisel | neat (SSH-based / HTTP-oriented) | another service for the same job; less operator documentation | No |
| Cloudflare Tunnel | zero VPS needed | requirement: maximum OSS, own infrastructure | Excluded |
| headscale / NetBird / Tailscale | excellent for *your own* devices | not for publishing a service to people who will not install a VPN client | Complementary, not a replacement |

**Decision: frp.** Reason: the constraint is the 1 GB VPS, and frp is the candidate with
the smallest footprint and the largest installed base for exactly this problem. The edge
stays a packet mover; it holds no certificates and no authorization logic.

**Consequence:** identity must live at home (section 3). That is also the better place
for it — the machine with the RAM and the data does the thinking.

**Revisit if:** a second VPS with ≥2 GB becomes available and you want identity at the
edge (then Pangolin), or if you need P2P/mesh access for many personal devices (then headscale/NetBird).

## 2. Reverse proxy and certificates (at home)

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Traefik** (65k★, MIT) | Docker provider: routes come from container labels, so a new service is a compose file; built-in ACME with lego (IONOS DNS-01); middlewares for forward-auth and security headers | dynamic config can feel indirect; more concepts than Caddy | **Chosen** |
| Caddy (78k★, Apache-2.0) | simplest config in the world, sensible TLS defaults, DNS-01 via plugins (built from source or official image) | label-driven service discovery needs `caddy-docker-proxy` (extra plugin); label support is not core | Strong alternative |
| Nginx Proxy Manager | GUI, easy | GUI-configured state is not in Git → breaks principle 1 | No |
| frps doing TLS itself | one hop fewer | puts certificates and routing on the smallest machine; config lives on the VPS, not in the repo | No |

**Decision: Traefik at home, TLS terminated at home with a wildcard cert** obtained via
DNS-01 (no inbound port 80/443 needed — necessary behind CGNAT).

**Revisit if:** you dislike label-driven config or want zero plugins → Caddy with a file-based config.

## 3. Identity / SSO

| Option | Pros | Cons | For this setup |
|---|---|---|---|
| **Authelia** (29k★, Apache-2.0) | light (~100–200 MB reported); forward-auth + OIDC provider; MFA (TOTP/WebAuthn); YAML config in Git; mature | no admin UI, users live in a file; no self-service onboarding | **Chosen (phase 1, forward-auth gate)** |
| Authentik (26k★) | full IdP: admin UI, self-service, OIDC/SAML/LDAP, per-app policies, outposts | heavier stack (server + worker + Postgres + Redis, commonly ~1–1.5 GB); more to maintain | Chosen once a second node exists |
| Keycloak (37k★) | enterprise standard, everything | Java, 700 MB–1 GB, complex for a family homelab | Overkill |
| Zitadel (15k★) | modern, good UX | another full IdP; no advantage here | Overkill |
| Tinyauth (8.4k★, AGPL) | tiny (tens of MB), dead simple forward-auth, container-native | few features, young project | Pragmatic alternative to Authelia |
| No auth, VPN for everything | simplest, smallest attack surface | family members must install/keep a VPN client; mobile apps behave inconsistently | Baseline for *private* services |

**Decision:** start with a **forward-auth gate in front of publicly exposed routes**
(Authelia; Tinyauth is the lighter alternative), and keep everything else VPN-only.
Full SSO is postponed because the services that would benefit most do not speak OIDC
natively (Vaultwarden without a fork, Paperless-ngx, Immich only partially),
while the cost lands on the RAM budget immediately.

**Revisit if:** you want self-service accounts and per-app policies, or you add services
with real OIDC support (Nextcloud, Forgejo, Grafana) → then Authentik on a second node.

## 4. Dashboard / homepage

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Homepage** (gethomepage, 33k★, GPL-3.0, active) | YAML config in Git (fits IaC), docker-label integration, service widgets, lightweight | YAML-heavy | **Chosen** |
| Glance (37k★, AGPL, active) | very clean look, single config file | younger, fewer integrations | Alternative |
| Dashy (27k★, MIT) | highly configurable, pretty | configuration can grow huge; more frontend weight | Alternative |
| Homarr (7k★) | friendly UI | **repository archived** (last push 2026-06) | No |
| Wiki/dashboard via SilverBullet | no extra service | not a status dashboard | Complementary |

**Decision: Homepage.** It is the only one whose configuration is naturally a file in the
repository, and it can read Docker labels so a new service appears without copy-paste.

## 5. Secrets

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **SOPS + age** (23k★ / 24k★) | encrypted values in Git, readable diffs, no server, key can be printed on paper | no rotation UI, no audit log; key handling is manual | **Chosen** |
| Infisical | UI, rotation, audit, injection | another service + database to run and back up | Later, if needed |
| OpenBao/Vault | industry standard, dynamic secrets | heavy, unseal/HA complexity, overkill | No |
| git-crypt | simple | all-or-nothing per file, no per-value encryption, weak tooling | No |

**Decision: SOPS + age**, with the private key stored offline (paper/USB). Bootstrap-only
exception: Vaultwarden's master account is set up by hand once.

## 6. Updates

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Renovate** (23k★) | pull requests with changelogs and digest pinning; you decide when; works with Forgejo | needs a runner/schedule and initial config | **Chosen** |
| WUD (4k★) | watches images, can auto-update, notifications | auto-update "at will" contradicts "review before change" | Optional notifier |
| Watchtower | trivial | silently changes running systems, exactly the HomelabOS problem | No |

**Decision: Renovate opens PRs; you merge.** Nothing updates itself in the background.

## 7. Monitoring

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| Beszel (26k★, MIT) | extremely light agent, host + container stats, alerts | not a full metrics platform | **Chosen (host)** |
| Uptime Kuma (93k★) | URL/port checks, status pages, many notification channels | per-check overhead, not a metrics store | **Chosen (URLs)** |
| Grafana + Prometheus + node_exporter | everything | ~1 GB+ RAM and three more services — the budget says no | Later, on a second node |
| Healthchecks / cron monitoring | catches silent backup failures | one more thing | Optional |

**Decision: Beszel + Uptime Kuma**, and backups additionally get a "did the last snapshot
succeed" check, because silence is the most common failure mode.

## 8. Storage

Covered in depth in `docs/08-storage.md`; summary of the decision:

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **mergerfs + SnapRAID** | mixed disk sizes, no striping → a single dead disk does not kill the pool, disks can spin down, file-level restore | parity is not real-time (sync is scheduled) | **Chosen** |
| ZFS (mirror or raidz) | checksums, snapshots, replication, integrity | needs ECC-fast RAM and equally sized disks, USB resets are painful, ARC competes with 16 GB | No (maybe for the system disk later) |
| mdraid + LVM | standard, well known | striping/whole-array failure modes; mixed sizes waste space | No |
| External NAS/SAN | clean separation | costs money, one more device | Later |

## 9. Platform and runtime

| Decision | Chosen | Alternatives considered | Reason |
|---|---|---|---|
| Hypervisor | **Proxmox VE** | plain Debian + Docker, NixOS, Proxmox Backup Server | VM/LXC isolation, snapshots, backup, huge community, and Home Assistant OS wants its own VM |
| Guest runtime | **Docker CE + Compose** | Podman + Quadlet, plain systemd units | Compose is the lingua franca of self-hosting; every project ships a compose file. Podman is the purist OSS choice but more papercuts |
| Autostart/health | `restart: unless-stopped` + systemd timers | Docker Swarm, k8s | simplest thing that works |

## 10. Infrastructure as Code

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **OpenTofu + cloud-init + Compose** | stateful, `plan` before `apply`, no drift, tiny learning curve vs k8s, readable in Git | you must keep a state file (backed up) | **Chosen** |
| Ansible | huge module ecosystem, agentless | no state by design, "touches everything" behaviour you experienced; imperative ordering | No |
| NixOS + nixos-anywhere + disko + sops-nix | the most reproducible answer possible: one repo, one command, declarative disks and secrets | steep learning curve (the Nix language), smaller operator community for homelab questions | Candidate for node 2 |
| Kubernetes GitOps (Flux, onedr0p/home-ops style) | best practice reference material, reconciliation, self-healing | cluster operations you explicitly do not want | No (patterns borrowed, cluster rejected) |
| HomelabOS / Umbrel / CasaOS / Runtipi | one-click services | they own the state, opaque overrides — the reason HomelabOS failed for you (archived since 2019) | No |

## 11. Borrowed patterns (no dependency, only inspiration)

| Source | What to copy |
|---|---|
| onedr0p/home-ops (Kubernetes/GitOps homelab, 2.9k★, very active) | repository layout, Renovate + digest pinning, SOPS/age usage, "recovery in minutes" documentation style |
| khuedoan/homelab (9.7k★) | "empty disk to running services with one command" mindset |
| Perfect Media Server (perfectmediaserver.com) | mergerfs + SnapRAID practice, disk-per-filesystem rule, parity sizing |
| community-scripts/ProxmoxVE (30k★) | reference recipes for running service X in an LXC |
| ChristianLempa/boilerplates (8k★) | Compose templates and conventions |
| awesome-selfhosted (327k★) | choosing services in the first place |

---

## Decision status

| # | Decision | Status |
|---|---|---|
| 1 | Edge transport = frp | proposed |
| 2 | Reverse proxy = Traefik, wildcard cert via DNS-01 | proposed |
| 3 | Auth gate = Authelia (or Tinyauth), full SSO postponed | proposed |
| 4 | Dashboard = Homepage | proposed |
| 5 | Secrets = SOPS + age | agreed |
| 6 | Updates = Renovate PRs | proposed |
| 7 | Monitoring = Beszel + Uptime Kuma | proposed |
| 8 | Storage = mergerfs + SnapRAID (largest disk as parity) | proposed |
| 9 | Platform = Proxmox + Docker Compose | agreed |
| 10 | IaC = OpenTofu + cloud-init + Compose | agreed |

*Mark a row as agreed, or change it — every row is reversible. The only expensive
decisions are storage layout and domain/DNS, because data and names are hard to move later.*
